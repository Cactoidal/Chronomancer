# Chronomancer
Smart contract endpoint and order-filling bot for fast, Chainlink CCIP-backed transfers.

## [Chronomancer](https://github.com/Cactoidal/Chronomancer/tree/main/Chronomancer)
[Release (MacOS, Ubuntu, Windows 10+ 64bit)](https://github.com/Cactoidal/Chronomancer/releases/tag/Chronomancer)

CCIP OnRamp monitoring bot that pulls EVM2EVM messages from source chains and instantly transfers tokens on destination chains.  Simply type any password to log in for the first time (write it down, or you won't be able to get back in if you forget!).   You can retrieve your address and private key from the Settings tab, so that you can easily fund your bot with testnet ETH and CCIP-BnM tokens.

## [TestCreator](https://github.com/Cactoidal/Chronomancer/tree/main/TestCreator)
[Release (MacOS, Ubuntu, Windows 10+ 64bit)](https://github.com/Cactoidal/Chronomancer/releases/tag/Chronomancer)  

For building your own simple CCIP test cases composed of sender and recipient networks.  It has built-in gas limits and an obligate minimum wait time of 10 seconds between transactions; these parameters can be changed in the Godot editor.  You can retrieve your address and key from the Settings tab.  The message-sending contract is configured to use sendMessagePayNative, so you only need to fund your senders with testnet ETH and CCIP-BnM tokens.
_______
The Chronomancer directory is a complete Godot project, and can be downloaded and imported directly into [Godot Engine Version 3.5.2](https://github.com/godotengine/godot/releases/tag/3.5.2-stable) for editing.  You can also download Chronomancer's application binary on the release page.  It contains compiled Rust libraries for MacOS and Ubuntu.  If you'd like to compile the Rust library from source, the code is available in the [rust folder](https://github.com/Cactoidal/Chronomancer/tree/main/rust).

The TestCreator directory is another complete Godot project, and just like Chronomancer can be either loaded directly into the Godot Engine, or the binary can be downloaded from the release page.
