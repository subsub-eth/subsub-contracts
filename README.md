# CreateZ Contracts

## Open TODOs

- merge: separate funds that are accumulated in the current sub and funds merged in, enable via flag
- separate sub deposits, tips, and maybe merged funds
- use a combined storage for subscription instead of each mixin having its own, gas optimiziation
- write individual mixin tests
- refactor token handling and internal/external representation to separate contract
- "upgrade"/migrate to other subscription: separate migrated funds from accumulated ones, enable via flag
- max donation / deposit
- allow 0 amount tip or check for a configurable min tip amount?
- refactor event deposited to spent amount?
- define metadata
- upgrade function / flow, migrating one token into another
- fast block time + small epoch size => out of gas?
- split owner and user sides into separate abstract contracts?
- use structs to combine fields/members?
- optimize variable sizes
- generate simple image on chain to illustrate sub status
- add royalties?
- add natspec comments
- write proper README
- add to docs the issue of not scaling epoch size, suggest size of 1 week or more

- change ERC721Ownable to ERC6551?!
