A protocol that allows a user to deposit into a vault and in return, receive rebase tokens that represent their underlying balance 
Rebase Token -> balanceOf function is dynamic to show the users changing balance over time.
    - Balance increases linearly over time
    - Mint tokens to users everytime they perform an action. (Minting, burning, transferring or bridging)
Interest Rate:
    - Indiviually set interest rate for each user based on global interest rate of the protocol at the time the user deposits into the vault.
    - This global interest rate can only decrease to incentivise early adoptors
    - Increase token adoption