While ScryPool is experimental, untested, and not part of the proof-of-concept, I wanted to include it because the idea potentially addresses one of Chronomancer's current limitations.

As presently designed, Chronomancer providers can only fill an order if they have enough tokens to fill the entire order.  ScryPool solves this problem by allowing multiple providers to trustlessly pool their tokens and collectively fill large orders.  This should greatly increase the system's overall capacity, and allow anyone to participate regardless of how many tokens they have.

For ScryPool to work, the Fast CCIP Endpoint would need to be slightly reconfigured to check whether an order filler's address is a contract, and send Any2EVM messages along with tokens.

I feel I should also mention here my thoughts on the fee.  The current fee is included for demonstration purposes, but in a real setting, users would likely want to set their own fee, while Chronomancer providers could choose which fees they are willing to accept.

To me, it seems the most efficient solution would be including the fee value in the CCIP message's data object, after the recipient address.
