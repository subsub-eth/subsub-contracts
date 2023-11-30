# CreateZ Contracts

## Open TODOs

- merge: separate funds that are accumulated in the current sub and funds merged in, enable via flag
- use a combined storage for subscription instead of each mixin having its own, gas optimiziation?
- write individual mixin tests
- change ERC721Ownable to ERC6551?!
- "upgrade"/migrate to other subscription: separate migrated funds from accumulated ones, enable via flag
- upgrade function / flow, migrating one token into another
- refactor event deposited to spent amount?
- define metadata
- optimize variable sizes
- add natspec comments
- write proper README
- add to docs the issue of not scaling epoch size, suggest size of 1 week or more

Nice to haves / add later:
- allow execute claim to owner by anyone to prevent epochSize scaling issue, claiming a reward
- allow 0 amount tip or check for a configurable min tip amount?
- max donation / deposit
- generate simple image on chain to illustrate sub status
- add royalties?

