"Ethers.gd" is a global singleton that can be accessed from any node.  It creates an HTTPRequest on demand, which calls back to a user-defined function on a user-defined node.  Perform any eth_method from anywhere by using:

Ethers.perform_request(  
    method,  
    params,  
    rpc,  
    retries,  
    callback_node,  
    callback_function,  
    callback_args={}  
    )  

Where "method" is the eth_method,  
"params" are the method parameters,  
"rpc" is a url for an rpc node for the network you're calling,  
"retries" is the initial retry count (usually set to 0, as it will increment up to 3 whenever retries are attempted),  
"callback_node" is the node that will receive the callback from the HTTPRequest,  
"callback_function" is the function that will be called on the callback node,  
and "callback_args" are any application-specific arguments you need to pass to the callback function.  

To get calldata for interacting with a contract, you will need to use a separate module, such as a GDNative library that uses ethers-rs via Godot Rust.  Please refer to this README for more information.
