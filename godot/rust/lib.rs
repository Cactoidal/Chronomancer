use gdnative::{prelude::*, core_types::ToVariant};
use ethers::{core::{abi::{struct_def::StructFieldType, AbiEncode, AbiDecode}, types::*, k256::elliptic_curve::consts::U8}, signers::*, providers::*, prelude::SignerMiddleware};
use ethers_contract::{abigen};
use ethers::core::types::transaction::eip2718::TypedTransaction;
use std::{convert::TryFrom, sync::Arc};
use tokio::runtime::{Builder, Runtime};
use tokio::task::LocalSet;
use tokio::macros::support::{Pin, Poll};
use futures::Future;
use hex::*;
use num_bigint::BigUint;

thread_local! {
    static EXECUTOR: &'static SharedLocalPool = {
        Box::leak(Box::new(SharedLocalPool::default()))
    };
}

#[derive(Default)]
struct SharedLocalPool {
    local_set: LocalSet,
}

impl futures::task::LocalSpawn for SharedLocalPool {
    fn spawn_local_obj(
        &self,
        future: futures::task::LocalFutureObj<'static, ()>,
    ) -> Result<(), futures::task::SpawnError> {
        self.local_set.spawn_local(future);

        Ok(())
    }
}


fn init(handle: InitHandle) {
    gdnative::tasks::register_runtime(&handle);
    gdnative::tasks::set_executor(EXECUTOR.with(|e| *e));

    handle.add_class::<FastCCIPBot>();
}

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

struct NewFuture(Result<(), Box<dyn std::error::Error + 'static>>);

impl ToVariant for NewFuture {
    fn to_variant(&self) -> Variant {todo!()}
}

struct NewStructFieldType(StructFieldType);

impl OwnedToVariant for NewStructFieldType {
    fn owned_to_variant(self) -> Variant {
        todo!()
    }
}

impl Future for NewFuture {
    type Output = NewStructFieldType;
    fn poll(self: Pin<&mut Self>, _: &mut std::task::Context<'_>) -> Poll<<Self as futures::Future>::Output> { todo!() }
}

#[derive(NativeClass, Debug, ToVariant, FromVariant)]
#[inherit(Node)]
struct FastCCIPBot;

#[methods]
impl FastCCIPBot {
    fn new(_owner: &Node) -> Self {
        FastCCIPBot
    }

#[method]
fn get_address(key: PoolArray<u8>) -> GodotString {

let vec = &key.to_vec();

let keyset = &vec[..]; 
 
let prewallet : LocalWallet = LocalWallet::from_bytes(&keyset).unwrap();

let wallet: LocalWallet = prewallet.with_chain_id(Chain::Sepolia);

let address = wallet.address();

let address_string = address.encode_hex();

let key_slice = match address_string.char_indices().nth(*&0 as usize) {
    Some((_pos, _)) => (&address_string[26..]).to_string(),
    None => "".to_string(),
    };

let return_string: GodotString = format!("0x{}", key_slice).into();

return_string

}



//   ORDER FILLING  //



//convert balance to evm-compatible via:
//U256::exp10(18) * amount


#[method]
#[tokio::main]
async fn fill_order(key: PoolArray<u8>, chain_id: u64, endpoint_contract: GodotString, rpc: GodotString, _gas_fee: u64, _count: u64, EVM2EVMMessage: GodotString, token_address: GodotString, ui_node: Ref<Node>) -> NewFuture {

let vec = &key.to_vec();

let keyset = &vec[..]; 
             
let prewallet : LocalWallet = LocalWallet::from_bytes(&keyset).unwrap();
        
let wallet: LocalWallet = prewallet.with_chain_id(chain_id);
        
let user_address = wallet.address();
        
let provider = Provider::<Http>::try_from(rpc.to_string()).expect("could not instantiate HTTP Provider");
        
let contract_address: Address = endpoint_contract.to_string().parse().unwrap();
        
let client = SignerMiddleware::new(provider, wallet.clone());
        
let contract = FastCCIPBotABI::new(contract_address.clone(), Arc::new(client.clone()));

let message_vec = hex::decode(EVM2EVMMessage.to_string()).unwrap();

let local_token_address: Address = token_address.to_string().parse().unwrap();

let calldata = contract.fill_order(message_vec.into(), local_token_address).calldata().unwrap();

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

let typed_tx: TypedTransaction = TypedTransaction::Eip1559(tx.clone());

let signature = wallet.sign_transaction(&typed_tx).await.unwrap();

let signed_data = TypedTransaction::rlp_signed(&typed_tx, &signature);

let node: TRef<Node> = unsafe { ui_node.assume_safe() };

unsafe {
    node.call("set_signed_data", &[hex::encode(signed_data).to_variant()])
};


NewFuture(Ok(()))

}


#[method]
fn filter_order(key: PoolArray<u8>, chain_id: u64, endpoint_contract: GodotString, rpc: GodotString, EVM2EVMMessage: GodotString, local_token_contracts: PoolArray<GodotString>, remote_token_contracts: PoolArray<GodotString>, token_minimums: PoolArray<GodotString>) -> GodotString {

let vec = &key.to_vec();

let keyset = &vec[..]; 
             
let prewallet : LocalWallet = LocalWallet::from_bytes(&keyset).unwrap();
        
let wallet: LocalWallet = prewallet.with_chain_id(chain_id);
        
let user_address = wallet.address();
        
let provider = Provider::<Http>::try_from(rpc.to_string()).expect("could not instantiate HTTP Provider");
        
let contract_address: Address = endpoint_contract.to_string().parse().unwrap();
        
let client = SignerMiddleware::new(provider, wallet.clone());
        
let contract = FastCCIPBotABI::new(contract_address.clone(), Arc::new(client.clone()));

let message_vec = hex::decode(EVM2EVMMessage.to_string()).unwrap();

let local_address_vec = &local_token_contracts.to_vec();

let local_address_string_vec: Vec<String> = local_address_vec.iter().map(|e| e.to_string() as String).collect();

let local_token_address_vec: Vec<Address> = local_address_string_vec.iter().map(|e|e.parse::<Address>().unwrap() as Address).collect();

let remote_address_vec = &remote_token_contracts.to_vec();

let remote_address_string_vec: Vec<String> = remote_address_vec.iter().map(|e| e.to_string() as String).collect();

let remote_token_address_vec: Vec<Address> = remote_address_string_vec.iter().map(|e|e.parse::<Address>().unwrap() as Address).collect();

let minimums_vec = &token_minimums.to_vec();

let string_minimums_vec: Vec<String> = minimums_vec.iter().map(|e| e.to_string() as String).collect();

let biguint_minimums_vec: Vec<BigUint> = string_minimums_vec.iter().map(|e|e.parse::<BigUint>().unwrap() as BigUint).collect();

let u256_minimums_vec: Vec<U256> = biguint_minimums_vec.iter().map(|e|U256::from_big_endian(e.to_bytes_be().as_slice()) as U256).collect();

let calldata = contract.filter_order(message_vec.into(), contract_address, user_address, local_token_address_vec, remote_token_address_vec, u256_minimums_vec).calldata().unwrap();

let return_string: GodotString = calldata.to_string().into();

return_string

}


//  ERC20 FUNCTIONS //


#[method]
fn check_token_balance(key: PoolArray<u8>, chain_id: u64, rpc: GodotString, token_contract: GodotString) -> GodotString {

let vec = &key.to_vec();

let keyset = &vec[..]; 
             
let prewallet : LocalWallet = LocalWallet::from_bytes(&keyset).unwrap();
        
let wallet: LocalWallet = prewallet.with_chain_id(chain_id);
        
let user_address = wallet.address();
        
let provider = Provider::<Http>::try_from(rpc.to_string()).expect("could not instantiate HTTP Provider");
        
let token_address: Address = token_contract.to_string().parse().unwrap();
        
let client = SignerMiddleware::new(provider, wallet.clone());
        
let contract = ERC20ABI::new(token_address.clone(), Arc::new(client.clone()));

let calldata = contract.balance_of(user_address).calldata().unwrap();

let return_string: GodotString = calldata.to_string().into();

return_string

}

#[method]
fn get_token_name(key: PoolArray<u8>, chain_id: u64, rpc: GodotString, token_contract: GodotString) -> GodotString {

let vec = &key.to_vec();

let keyset = &vec[..]; 
             
let prewallet : LocalWallet = LocalWallet::from_bytes(&keyset).unwrap();
        
let wallet: LocalWallet = prewallet.with_chain_id(chain_id);
        
let provider = Provider::<Http>::try_from(rpc.to_string()).expect("could not instantiate HTTP Provider");
        
let token_address: Address = token_contract.to_string().parse().unwrap();
        
let client = SignerMiddleware::new(provider, wallet.clone());
        
let contract = ERC20ABI::new(token_address.clone(), Arc::new(client.clone()));

let calldata = contract.name().calldata().unwrap();

let return_string: GodotString = calldata.to_string().into();

return_string

}

#[method]
fn get_token_decimals(key: PoolArray<u8>, chain_id: u64, rpc: GodotString, token_contract: GodotString) -> GodotString {

let vec = &key.to_vec();

let keyset = &vec[..]; 
             
let prewallet : LocalWallet = LocalWallet::from_bytes(&keyset).unwrap();
        
let wallet: LocalWallet = prewallet.with_chain_id(chain_id);
        
let provider = Provider::<Http>::try_from(rpc.to_string()).expect("could not instantiate HTTP Provider");
        
let token_address: Address = token_contract.to_string().parse().unwrap();
        
let client = SignerMiddleware::new(provider, wallet.clone());
        
let contract = ERC20ABI::new(token_address.clone(), Arc::new(client.clone()));

let calldata = contract.decimals().calldata().unwrap();

let return_string: GodotString = calldata.to_string().into();

return_string

}


#[method]
fn check_endpoint_allowance(key: PoolArray<u8>, chain_id: u64, rpc: GodotString, token_contract: GodotString, endpoint_contract: GodotString) -> GodotString {

let vec = &key.to_vec();

let keyset = &vec[..]; 
             
let prewallet : LocalWallet = LocalWallet::from_bytes(&keyset).unwrap();
        
let wallet: LocalWallet = prewallet.with_chain_id(chain_id);
        
let user_address = wallet.address();
        
let provider = Provider::<Http>::try_from(rpc.to_string()).expect("could not instantiate HTTP Provider");
        
let token_address: Address = token_contract.to_string().parse().unwrap();

let endpoint_address: Address = endpoint_contract.to_string().parse().unwrap();
        
let client = SignerMiddleware::new(provider, wallet.clone());
        
let contract = ERC20ABI::new(token_address.clone(), Arc::new(client.clone()));

let calldata = contract.allowance(user_address, endpoint_address).calldata().unwrap();

let return_string: GodotString = calldata.to_string().into();

return_string

}


#[method]
#[tokio::main]
async fn approve_endpoint_allowance(key: PoolArray<u8>, chain_id: u64, endpoint_contract: GodotString, rpc: GodotString, _gas_fee: u64, _count: u64, token_contract: GodotString, ui_node: Ref<Node>) -> NewFuture {

let vec = &key.to_vec();

let keyset = &vec[..]; 
             
let prewallet : LocalWallet = LocalWallet::from_bytes(&keyset).unwrap();
        
let wallet: LocalWallet = prewallet.with_chain_id(chain_id);
        
let user_address = wallet.address();
        
let provider = Provider::<Http>::try_from(rpc.to_string()).expect("could not instantiate HTTP Provider");
        
let client = SignerMiddleware::new(provider, wallet.clone());

let endpoint_address: Address = endpoint_contract.to_string().parse().unwrap();

let token_address: Address = token_contract.to_string().parse().unwrap();

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

let typed_tx: TypedTransaction = TypedTransaction::Eip1559(tx.clone());

let signature = wallet.sign_transaction(&typed_tx).await.unwrap();

let signed_data = TypedTransaction::rlp_signed(&typed_tx, &signature);

let node: TRef<Node> = unsafe { ui_node.assume_safe() };

unsafe {
    node.call("set_signed_data", &[hex::encode(signed_data).to_variant()])
};


NewFuture(Ok(()))

}



// TEST SENDER //


#[method]
#[tokio::main]
async fn test_send(key: PoolArray<u8>, chain_id: u64, entrypoint_contract: GodotString, rpc: GodotString, _gas_fee: u64, _count: u64, _chain_selector: GodotString, endpoint_contract: GodotString, recipient: GodotString, _data: GodotString, token_address: GodotString, amount: GodotString, _value: GodotString, ui_node: Ref<Node>) -> NewFuture {

let vec = &key.to_vec();

let keyset = &vec[..]; 
             
let prewallet : LocalWallet = LocalWallet::from_bytes(&keyset).unwrap();
        
let wallet: LocalWallet = prewallet.with_chain_id(chain_id);
        
let user_address = wallet.address();
        
let provider = Provider::<Http>::try_from(rpc.to_string()).expect("could not instantiate HTTP Provider");
        
let contract_address: Address = entrypoint_contract.to_string().parse().unwrap();
        
let client = SignerMiddleware::new(provider, wallet.clone());
        
let contract = TestSenderABI::new(contract_address.clone(), Arc::new(client.clone()));

let chain_selector: u64 = _chain_selector.to_string().parse::<u64>().unwrap();

let endpoint_address: Address = endpoint_contract.to_string().parse().unwrap();

let recipient_address: Address = recipient.to_string().parse().unwrap();

let data_string: String = _data.to_string();

let data_bytes = hex::decode(data_string).unwrap();
    
let data: Bytes = data_bytes.into();

let local_token_address: Address = token_address.to_string().parse().unwrap();

let big_uint_amount: BigUint = amount.to_string().parse().unwrap();

let token_amount: U256 = U256::from_big_endian(big_uint_amount.to_bytes_be().as_slice());

let big_uint_value: BigUint = _value.to_string().parse().unwrap();

let value: U256 = U256::from_big_endian(big_uint_value.to_bytes_be().as_slice());

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

let typed_tx: TypedTransaction = TypedTransaction::Eip1559(tx.clone());

let signature = wallet.sign_transaction(&typed_tx).await.unwrap();

let signed_data = TypedTransaction::rlp_signed(&typed_tx, &signature);

let node: TRef<Node> = unsafe { ui_node.assume_safe() };

unsafe {
    node.call("set_signed_data", &[hex::encode(signed_data).to_variant()])
};


NewFuture(Ok(()))

}


#[method]
fn get_fee_value(key: PoolArray<u8>, chain_id: u64, entrypoint_contract: GodotString, rpc: GodotString, _gas_fee: u64, _count: u64, _chain_selector: GodotString, endpoint_contract: GodotString, recipient: GodotString, _data: GodotString, token_address: GodotString, amount: GodotString) -> GodotString {

let vec = &key.to_vec();

let keyset = &vec[..]; 
             
let prewallet : LocalWallet = LocalWallet::from_bytes(&keyset).unwrap();
        
let wallet: LocalWallet = prewallet.with_chain_id(chain_id);
        
let provider = Provider::<Http>::try_from(rpc.to_string()).expect("could not instantiate HTTP Provider");
        
let contract_address: Address = entrypoint_contract.to_string().parse().unwrap();
        
let client = SignerMiddleware::new(provider, wallet.clone());
        
let contract = TestSenderABI::new(contract_address.clone(), Arc::new(client.clone()));

let chain_selector: u64 = _chain_selector.to_string().parse::<u64>().unwrap();

let endpoint_address: Address = endpoint_contract.to_string().parse().unwrap();

let recipient_address: Address = recipient.to_string().parse().unwrap();

let data_string: String = _data.to_string();

let data_bytes = hex::decode(data_string).unwrap();
    
let data: Bytes = data_bytes.into();

let local_token_address: Address = token_address.to_string().parse().unwrap();

let big_uint_amount: BigUint = amount.to_string().parse().unwrap();

let token_amount: U256 = U256::from_big_endian(big_uint_amount.to_bytes_be().as_slice());

let calldata = contract.get_native_fee_value(chain_selector, endpoint_address, recipient_address, data, local_token_address, token_amount).calldata().unwrap();

let return_string: GodotString = calldata.to_string().into();

return_string

}


// HELPER FUNCTIONS //

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
    //let bytes: Bytes = ethers::abi::AbiDecode::decode_hex(raw_hex).unwrap();
    let decoded_bytes: [U256; 5] = ethers::abi::AbiDecode::decode_hex(raw_hex).unwrap();
    godot_print!("{:?}", decoded_bytes);
    let return_string: GodotString = format!("{:?}", decoded_bytes).into();
    return_string
}




//  EXPERIMENTAL //
#[method]
fn get_function_selector(function_bytes: PoolArray<u8>) -> GodotString {
    let selector_bytes = ethers::utils::keccak256(&function_bytes.to_vec()[..]);
    
    let selector = hex::encode(selector_bytes);
    
    selector.to_string().into()

}



#[method]
#[tokio::main]
async fn get_signed_calldata(key: PoolArray<u8>, chain_id: u64, _gas_limit: GodotString, _gas_fee: u64, _count: u64, _contract_address: GodotString, _value: GodotString, _calldata: String, ui_node: Ref<Node>) -> NewFuture {
             
let wallet : LocalWallet = LocalWallet::from_bytes(&key.to_vec()[..]).unwrap().with_chain_id(chain_id);
                
let user_address = wallet.address();
        
let contract_address: Address = _contract_address.to_string().parse().unwrap();

let big_uint_gas_limit: BigUint = _gas_limit.to_string().parse().unwrap();

let gas_limit: U256 = U256::from_big_endian(big_uint_gas_limit.to_bytes_be().as_slice());

let big_uint_value: BigUint = _value.to_string().parse().unwrap();

let value: U256 = U256::from_big_endian(big_uint_value.to_bytes_be().as_slice());

let calldata_bytes = hex::decode(_calldata).unwrap();

let calldata: Bytes = calldata_bytes.into();

let tx = Eip1559TransactionRequest::new()
    .from(user_address)
    .to(contract_address) 
    .value(value)
    .gas(gas_limit) //recommend 900000
    .max_fee_per_gas(_gas_fee)
    .max_priority_fee_per_gas(_gas_fee)
    .chain_id(chain_id)
    .nonce(_count)
    .data(calldata);

let typed_tx: TypedTransaction = TypedTransaction::Eip1559(tx.clone());

let signature = wallet.sign_transaction(&typed_tx).await.unwrap();

let signed_data = TypedTransaction::rlp_signed(&typed_tx, &signature);

let node: TRef<Node> = unsafe { ui_node.assume_safe() };

unsafe {
    node.call("set_signed_data", &[hex::encode(signed_data).to_variant()])
};

NewFuture(Ok(()))

}

#[method]
fn encode_address (_address: GodotString) -> GodotString {
    let address: Address = _address.to_string().parse().unwrap();
    let encoded = ethers::abi::AbiEncode::encode(address);
    let return_string: GodotString = hex::encode(encoded).into();
    return_string
}

#[method]
fn encode_u256 (_big_uint: GodotString) -> GodotString {
    let big_uint: BigUint = _big_uint.to_string().parse().unwrap();
    let u256: U256 = U256::from_big_endian(big_uint.to_bytes_be().as_slice());
    let encoded = ethers::abi::AbiEncode::encode(u256);
    let return_string: GodotString = hex::encode(encoded).into();
    return_string
}

#[method]
fn encode_u256_array (_big_uints: PoolArray<GodotString>) -> GodotString {

    let big_uint_strings: Vec<String> = _big_uints.to_vec().iter().map(|e| e.to_string() as String).collect();

    let big_uint_vec: Vec<BigUint> = big_uint_strings.iter().map(|e|e.parse::<BigUint>().unwrap() as BigUint).collect();

    let u256_vec: Vec<U256> = big_uint_vec.iter().map(|e|U256::from_big_endian(e.to_bytes_be().as_slice()) as U256).collect();

    let encoded = ethers::abi::AbiEncode::encode_hex(u256_vec);

    let return_string: GodotString = format!("{:?}", encoded).into();

    return_string
}

#[method]
fn encode_bytes (message: GodotString) -> GodotString {

    godot_print!("message: {:?}", message);

    let hex_message = hex::encode(message.to_string());

    godot_print!("hex message: {:?}", hex_message);

    let bytes: Bytes = hex::decode(hex_message).unwrap().into();

    godot_print!("bytes: {:?}", bytes);

    let encoded = ethers::abi::AbiEncode::encode_hex(bytes);

    let return_string: GodotString = format!("{:?}", encoded).into();

    return_string
}



#[method]
fn get_hex_bytes (message: GodotString) -> PoolArray<u8> {

    let message_vec = hex::decode(message.to_string()).unwrap();

    let mut pool_byte_array = PoolArray::<u8>::new();
  
    pool_byte_array.resize(message_vec.len() as i32);
  
    for (i, byte) in message_vec.iter().enumerate() {
        pool_byte_array.set(i as i32, *byte);
    }
 
    pool_byte_array.into()


}

#[method]
fn old_encode_bytes (byte_array: PoolArray<u8>) -> GodotString {

    let bytes: Bytes = byte_array.to_vec().into();

    let encoded = ethers::abi::AbiEncode::encode(bytes);

    let return_string: GodotString = hex::encode(encoded).into();

    return_string
}

#[method]
fn another_encode_bytes (byte_array: PoolArray<u8>) -> GodotString {

    let bytes: Bytes = byte_array.to_vec().into();

    let abi_bytes = ethers::abi::AbiEncode::encode(bytes);

    let hex = hex::encode(abi_bytes);

    hex.into()

}

#[method]
fn yet_another_encode_bytes (byte_array: PoolArray<u8>) -> GodotString {

    let abi_bytes = ethers::abi::encode_packed(&[ethers::abi::Token::Bytes(byte_array.to_vec())]).unwrap();

    let hex = hex::encode(abi_bytes);

    hex.into()

}

#[method]
fn also_encode_string (_string: GodotString) -> GodotString {

    let abi_bytes = ethers::abi::encode_packed(&[ethers::abi::Token::String(_string.to_string())]).unwrap();

    let hex = hex::encode(abi_bytes);

    hex.into()

}






}



godot_init!(init);

