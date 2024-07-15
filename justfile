alias b := build
alias t := test

default:
  just --list

# build
build:
  forge build --sizes --extra-output-files abi

# build all
build-all: build test typechain pnpm-pack

# generate typechain types
typechain:
  pnpm run generate-types

# pnpm pack
pnpm-pack:
  pnpm pack

# test deploy to anvil
deploy-local:
  forge script script/Deploy.s.sol:DeployScript --fork-url http://localhost:8545 --broadcast

# test deploy to anvil with test data
test-deploy-local $DEPLOY_TEST_DATA="true":
  forge script script/Deploy.s.sol:DeployScript --fork-url http://localhost:8545 --broadcast


# test
test:
  forge test -vvv

# test contract
test-contract CONTRACT:
  forge test -vvv --match-contract {{CONTRACT}}

# clean all
clean: forge-clean pnpm-clean

forge-clean:
  forge clean

pnpm-clean:
  pnpm clean