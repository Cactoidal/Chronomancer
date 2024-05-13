use gdnative::{prelude::*, core_types::ToVariant};
use ethers::{core::{abi::{AbiDecode, AbiEncode}, k256::elliptic_curve::consts::{U248, U8}, types::*}, prelude::SignerMiddleware, providers::*, signers::*};
use ethers_contract::{abigen};
use ethers::core::types::transaction::eip2718::TypedTransaction;
use std::{convert::TryFrom, sync::Arc};
use hex::*;
use num_bigint::{BigUint, BigInt};


// Declare ABIs here.  ABI files only need to be present when compiling, they
// do not need to be in the application files.

abigen!(
    FastCCIPBotABI,
    "./FastCCIPBot.json",
    event_derives(serde::Deserialize, serde::Serialize)
);

abigen!(
    ERC20ABI,
    "./ERC20.json",
    event_derives(serde::Deserialize, serde::Serialize)
);

abigen!(
    TestSenderABI,
    "./TestSender.json",
    event_derives(serde::Deserialize, serde::Serialize)
);

fn init(handle: InitHandle) {
    
    // Name of the Godot Class for the GDNative Library
    handle.add_class::<FastCCIPBot>();
}

#[derive(NativeClass, Debug, ToVariant, FromVariant)]
#[inherit(Node)]

struct FastCCIPBot;

#[methods]
impl FastCCIPBot {
    fn new(_owner: &Node) -> Self {
        FastCCIPBot
    }


//   Application methods go here.  These will be callable from gdscript in Godot


//          ORDER FILLING METHODS         //

#[method]
fn fill_order(key: PoolArray<u8>, _chain_id: GodotString, endpoint_contract: GodotString, rpc: GodotString, _gas_fee: u64, _count: u64, EVM2EVMMessage: GodotString, token_address: GodotString) -> GodotString {

    let (wallet, chain_id, user_address, client) = get_signer(key, _chain_id, rpc);

    let contract_address = string_to_address(endpoint_contract);

    let contract = FastCCIPBotABI::new(contract_address.clone(), Arc::new(client.clone()));

    let message = string_to_bytes(EVM2EVMMessage);

    let local_token_address = string_to_address(token_address);

    let calldata = contract.fill_order(message, local_token_address).calldata().unwrap();

    let tx = Eip1559TransactionRequest::new()
        .from(user_address)
        .to(contract_address) 
        .value(0)
        .gas(900000)
        .max_fee_per_gas(_gas_fee)
        .max_priority_fee_per_gas(_gas_fee)
        .chain_id(chain_id)
        .nonce(_count)
        .data(calldata);

        let signed_calldata = get_signed_calldata(tx, wallet);

        signed_calldata
}



#[method]
fn filter_order(key: PoolArray<u8>, _chain_id: GodotString, endpoint_contract: GodotString, rpc: GodotString, EVM2EVMMessage: GodotString, _local_token_contracts: PoolArray<GodotString>, _remote_token_contracts: PoolArray<GodotString>, _token_minimums: PoolArray<GodotString>) -> GodotString {

    let (wallet, chain_id, user_address, client) = get_signer(key, _chain_id, rpc);
            
    let contract_address = string_to_address(endpoint_contract);
            
    let contract = FastCCIPBotABI::new(contract_address.clone(), Arc::new(client.clone()));

    let message = string_to_bytes(EVM2EVMMessage);

    let local_token_contracts = string_array_to_addresses(_local_token_contracts);

    let remote_token_contracts = string_array_to_addresses(_remote_token_contracts);

    let token_minimums = string_array_to_uint256s(_token_minimums);

    let calldata = contract.filter_order(message, contract_address, user_address, local_token_contracts, remote_token_contracts, token_minimums).calldata().unwrap();

    let return_string: GodotString = calldata.to_string().into();

    return_string

}



//      ERC20 METHODS     //

#[method]
fn check_token_balance(key: PoolArray<u8>, _chain_id: GodotString, rpc: GodotString, token_contract: GodotString) -> GodotString {

    let (wallet, chain_id, user_address, client) = get_signer(key, _chain_id, rpc);
            
    let token_address: Address = string_to_address(token_contract);
            
    let contract = ERC20ABI::new(token_address.clone(), Arc::new(client.clone()));

    let calldata = contract.balance_of(user_address).calldata().unwrap();

    let return_string: GodotString = calldata.to_string().into();

    return_string

}

#[method]
fn get_token_name(key: PoolArray<u8>, _chain_id: GodotString, rpc: GodotString, token_contract: GodotString) -> GodotString {

    let (wallet, chain_id, user_address, client) = get_signer(key, _chain_id, rpc);
            
    let token_address = string_to_address(token_contract);
            
    let contract = ERC20ABI::new(token_address.clone(), Arc::new(client.clone()));

    let calldata = contract.name().calldata().unwrap();

    let return_string: GodotString = calldata.to_string().into();

    return_string

}

#[method]
fn get_token_decimals(key: PoolArray<u8>, _chain_id: GodotString, rpc: GodotString, token_contract: GodotString) -> GodotString {

    let (wallet, chain_id, user_address, client) = get_signer(key, _chain_id, rpc);
            
    let token_address = string_to_address(token_contract);
            
    let contract = ERC20ABI::new(token_address.clone(), Arc::new(client.clone()));

    let calldata = contract.decimals().calldata().unwrap();

    let return_string: GodotString = calldata.to_string().into();

    return_string

}


#[method]
fn check_endpoint_allowance(key: PoolArray<u8>, _chain_id: GodotString, rpc: GodotString, token_contract: GodotString, endpoint_contract: GodotString) -> GodotString {

    let (wallet, chain_id, user_address, client) = get_signer(key, _chain_id, rpc);
            
    let token_address = string_to_address(token_contract);

    let endpoint_address = string_to_address(endpoint_contract);
            
    let contract = ERC20ABI::new(token_address.clone(), Arc::new(client.clone()));

    let calldata = contract.allowance(user_address, endpoint_address).calldata().unwrap();

    let return_string: GodotString = calldata.to_string().into();

    return_string

}


#[method]
fn approve_endpoint_allowance(key: PoolArray<u8>, _chain_id: GodotString, endpoint_contract: GodotString, rpc: GodotString, _gas_fee: u64, _count: u64, token_contract: GodotString) -> GodotString {

    let (wallet, chain_id, user_address, client) = get_signer(key, _chain_id, rpc);

    let endpoint_address = string_to_address(endpoint_contract);

    let token_address = string_to_address(token_contract);

    let contract = ERC20ABI::new(token_address.clone(), Arc::new(client.clone()));

    let calldata = contract.approve(endpoint_address, U256::MAX).calldata().unwrap();

    let tx = Eip1559TransactionRequest::new()
        .from(user_address)
        .to(token_address) 
        .value(0)
        .gas(900000)
        .max_fee_per_gas(_gas_fee)
        .max_priority_fee_per_gas(_gas_fee)
        .chain_id(chain_id)
        .nonce(_count)
        .data(calldata);

    let signed_calldata = get_signed_calldata(tx, wallet);

    signed_calldata

}



//          TEST SENDER METHODS       //


#[method]
fn test_send(key: PoolArray<u8>, _chain_id: GodotString, entrypoint_contract: GodotString, rpc: GodotString, _gas_fee: u64, _count: u64, _chain_selector: GodotString, endpoint_contract: GodotString, recipient: GodotString, _data: GodotString, token_address: GodotString, amount: GodotString, _value: GodotString) -> GodotString {

    let (wallet, chain_id, user_address, client) = get_signer(key, _chain_id, rpc);
            
    let contract_address = string_to_address(entrypoint_contract);
            
    let contract = TestSenderABI::new(contract_address.clone(), Arc::new(client.clone()));

    let chain_selector: u64 = _chain_selector.to_string().parse::<u64>().unwrap();

    let endpoint_address = string_to_address(endpoint_contract);

    let recipient_address = string_to_address(recipient);
        
    let data = string_to_bytes(_data);

    let local_token_address = string_to_address(token_address);

    let token_amount = string_to_uint256(amount);

    let value = string_to_uint256(_value);

    let calldata = contract.send_message_pay_native(chain_selector, endpoint_address, recipient_address, data, local_token_address, token_amount).calldata().unwrap();

    let tx = Eip1559TransactionRequest::new()
        .from(user_address)
        .to(contract_address) 
        .value(value)
        .gas(900000)
        .max_fee_per_gas(_gas_fee)
        .max_priority_fee_per_gas(_gas_fee)
        .chain_id(chain_id)
        .nonce(_count)
        .data(calldata);

    let signed_calldata = get_signed_calldata(tx, wallet);

    signed_calldata

}


#[method]
fn get_fee_value(key: PoolArray<u8>, _chain_id: GodotString, entrypoint_contract: GodotString, rpc: GodotString, _gas_fee: u64, _count: u64, _chain_selector: GodotString, endpoint_contract: GodotString, recipient: GodotString, _data: GodotString, token_address: GodotString, amount: GodotString) -> GodotString {

    let (wallet, chain_id, user_address, client) = get_signer(key, _chain_id, rpc);
        
    let contract_address = string_to_address(entrypoint_contract);
            
    let contract = TestSenderABI::new(contract_address.clone(), Arc::new(client.clone()));

    let chain_selector: u64 = _chain_selector.to_string().parse::<u64>().unwrap();

    let endpoint_address = string_to_address(endpoint_contract);

    let recipient_address = string_to_address(recipient);

    let data = string_to_bytes(_data);

    let local_token_address = string_to_address(token_address);

    let token_amount = string_to_uint256(amount);

    let calldata = contract.get_native_fee_value(chain_selector, endpoint_address, recipient_address, data, local_token_address, token_amount).calldata().unwrap();

    let return_string: GodotString = calldata.to_string().into();

    return_string

}



//      HELPER METHODS        //

// Mostly for decoding RPC responses

#[method]
fn get_address(key: PoolArray<u8>) -> GodotString {

    let wallet : LocalWallet = LocalWallet::from_bytes(&key.to_vec()[..]).unwrap();

    let address = wallet.address();

    let address_string = address.encode_hex();

    let key_slice = match address_string.char_indices().nth(*&0 as usize) {
        Some((_pos, _)) => (&address_string[26..]).to_string(),
        None => "".to_string(),
        };

    let return_string: GodotString = format!("0x{}", key_slice).into();

    return_string

}

#[method]
fn decode_hex_string (message: GodotString) -> GodotString {
    let raw_hex: String = message.to_string();
    let decoded: String = ethers::abi::AbiDecode::decode_hex(raw_hex).unwrap();
    let return_string: GodotString = decoded.into();
    return_string
}

#[method]
fn decode_bool (message: GodotString) -> GodotString {
    let raw_hex: String = message.to_string();
    let decoded: bool = ethers::abi::AbiDecode::decode_hex(raw_hex).unwrap();
    let return_string: GodotString = format!("{:?}", decoded).into();
    return_string
}

#[method]
fn decode_u8 (message: GodotString) -> GodotString {
    let raw_hex: String = message.to_string();
    let decoded: u8 = ethers::abi::AbiDecode::decode_hex(raw_hex).unwrap();
    let return_string: GodotString = format!("{:?}", decoded).into();
    return_string
}

#[method]
fn decode_address (message: GodotString) -> GodotString {
    let raw_hex: String = message.to_string();
    let decoded: Address = ethers::abi::AbiDecode::decode_hex(raw_hex).unwrap();
    let return_string: GodotString = format!("{:?}", decoded).into();
    return_string
}

#[method]
fn decode_bytes (message: GodotString) -> GodotString {
    let raw_hex: String = message.to_string();
    let decoded: Bytes = ethers::abi::AbiDecode::decode_hex(raw_hex).unwrap();
    let return_string: GodotString = format!("{:?}", decoded).into();
    return_string
}

#[method]
fn decode_u256 (message: GodotString) -> GodotString {
    let raw_hex: String = message.to_string();
    let decoded: U256 = ethers::abi::AbiDecode::decode_hex(raw_hex).unwrap();
    let return_string: GodotString = format!("{:?}", decoded).into();
    return_string
}



#[method]
fn decode_u256_array (message: GodotString) -> GodotString {
    let raw_hex: String = message.to_string();
    let decoded: Vec<U256> = ethers::abi::AbiDecode::decode_hex(raw_hex).unwrap();
    let return_string: GodotString = format!("{:?}", decoded).into();
    return_string
}


#[method]
fn decode_u256_array_from_bytes (message: GodotString) -> GodotString {
    let raw_hex: String = message.to_string();
    let decoded_bytes: [U256; 5] = ethers::abi::AbiDecode::decode_hex(raw_hex).unwrap();
    godot_print!("{:?}", decoded_bytes);
    let return_string: GodotString = format!("{:?}", decoded_bytes).into();
    return_string
}


}


// Initializes all the Godot class methods defined above

godot_init!(init);




//      UTILITY FUNCTIONS       //

// Common type conversions and operations


fn get_signer(key: PoolArray<u8>, _chain_id: GodotString, rpc: GodotString) -> (LocalWallet, u64, Address, SignerMiddleware<Provider<Http>, LocalWallet>) {
    
    let chain_id: u64 = _chain_id.to_string().parse::<u64>().unwrap();

    let wallet : LocalWallet = LocalWallet::from_bytes(&key.to_vec()[..]).unwrap().with_chain_id(chain_id);

    let user_address = wallet.address();
            
    let provider = Provider::<Http>::try_from(rpc.to_string()).expect("could not instantiate HTTP Provider");

    let client = SignerMiddleware::new(provider, wallet.clone());

    (wallet, chain_id, user_address, client)
}

fn get_signed_calldata(tx: Eip1559TransactionRequest, wallet: LocalWallet) -> GodotString {

    let typed_tx: TypedTransaction = TypedTransaction::Eip1559(tx.clone());

    let signature = wallet.sign_transaction_sync(&typed_tx).unwrap();

    let rlp_signed = TypedTransaction::rlp_signed(&typed_tx, &signature);

    let signed_calldata = hex::encode(rlp_signed);

    signed_calldata.into()
}


fn string_to_bytes(_string: GodotString) -> Bytes {

    let string: String = _string.to_string();

    let byte_array = hex::decode(string).unwrap();
        
    let bytes: Bytes = byte_array.into();

    bytes
}

fn string_to_address(_string: GodotString) -> Address {

    let address: Address = _string.to_string().parse().unwrap();

    address
}

fn string_array_to_addresses(_godot_string_array: PoolArray<GodotString>) -> Vec<Address> {
    let godot_string_vec = &_godot_string_array.to_vec();

    let string_vec: Vec<String> = godot_string_vec.iter().map(|e| e.to_string() as String).collect();

    let address_vec: Vec<Address> = string_vec.iter().map(|e|e.parse::<Address>().unwrap() as Address).collect();

    address_vec
}

fn string_to_uint256(_string: GodotString) -> U256 {

    let big_uint: BigUint = _string.to_string().parse().unwrap();

    let u256: U256 = U256::from_big_endian(big_uint.to_bytes_be().as_slice());

    u256

}

fn string_array_to_uint256s(_godot_string_array: PoolArray<GodotString>) -> Vec<U256> {
    let godot_string_vec = &_godot_string_array.to_vec();

    let string_vec: Vec<String> = godot_string_vec.iter().map(|e| e.to_string() as String).collect();

    let big_uint_vec: Vec<BigUint> = string_vec.iter().map(|e|e.parse::<BigUint>().unwrap() as BigUint).collect();

    let u256_vec: Vec<U256> = big_uint_vec.iter().map(|e|U256::from_big_endian(e.to_bytes_be().as_slice()) as U256).collect();

    u256_vec
}




