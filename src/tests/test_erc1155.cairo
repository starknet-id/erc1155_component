use starknet::ContractAddress;
use starknet::testing;
use starknet::testing::set_contract_address;
use core::debug::PrintTrait;

use erc1155_component::interface::{ERC1155ABIDispatcher, ERC1155ABIDispatcherTrait};
use super::utils::common::deploy_contract;

#[test]
#[available_gas(20000000000)]
fn test_deploy() {
    let (erc1155, owner) = deploy_contract();
    let token_id = 1025;

    let balance = erc1155.balanceOf(owner, token_id);
    balance.print();
}
