# CreateZ Contracts

CreateZ is permissionless, flexible crypto subscription system that is a
building block for larger applications and communities.

It allows creators, companies, and whoever wants to collect crypto funds over a
long period of time to create various subscription plans with different settings
tailored to their needs.

Subscribers can join these contracts by depositing ERC20 tokens. These are
distributed to the contract owner exactly to the second. Depending on the plan's
settings this gives the subscriber control over their subscription allowing them
to cancel and refund unspent funds without hassle.

Subscriptions are represented as ERC721 tokens that accumulate stats on spent
funds. These properties can be used to unlock achievements or gain access to
parts of a creator's community.

As we strive to incorporate standards like ERC20 and ERC721 the system and its
participants and take part in the larger DeFi ecosystem by for example using
yield bearing tokens for payments or selling community memberships on secondary
markets. The possibilities are endless.

The system is open-source and free to use. You can choose to deploy your own
fork or use the deployed contracts. We also provide a functional but generic web
interface as an example for your own community.

We do not charge any fees.

## Development

The project uses foundry for compiling, testing, and deployment of contracts.
PNPM and typechain are used to generate typescript types that are published to
the NPM registry. These are used in the frontend.

Building:

```
forge clean
forge build --sizes
```

Testing:

```
forge test -vv
```

Local test deployment:

```
anvil &
pnpm run deploy-local
```

The local test deployment uses anvil's default test mnemonic to deploy the
system contracts, test tokens, public infrastructure, and some test data.
Relevant contracts are printed as logs

## Open TODOs

- merge: separate funds that are accumulated in the current sub and funds merged
  in, enable via flag
- use a combined storage for subscription instead of each mixin having its own,
  gas optimiziation?
- Subscription: move state variables to storage structs
- write individual mixin tests
- "upgrade"/migrate to other subscription: separate migrated funds from
  accumulated ones, enable via flag
- upgrade function / flow, migrating one token into another
- refactor event deposited to spent amount?
- define metadata
- optimize variable sizes
- add natspec comments
- write proper README
- add to docs the issue of not scaling epoch size, suggest size of 1 week or
  more

Nice to haves / add later:

- allow execute claim to owner by anyone to prevent epochSize scaling issue,
  claiming a reward
- allow 0 amount tip or check for a configurable min tip amount?
- max donation / deposit
- generate simple image on chain to illustrate sub status
- add royalties?