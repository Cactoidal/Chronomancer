### Develop Log

Instead of using an order path, it may be more efficient to first convert the EVM2EVM message to an Any2EVM message (supplying the local token address during the conversion), 
and when filling the order, map the message's ABI-encoded bytes to the order filler's address.
