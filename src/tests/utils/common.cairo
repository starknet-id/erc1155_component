use starknet::{class_hash::Felt252TryIntoClassHash, ContractAddress, SyscallResultTrait};
use starknet::testing::set_contract_address;
use core::array::ArrayTrait;
use erc1155_component::interface::{ERC1155ABIDispatcher, ERC1155ABIDispatcherTrait};
use erc1155_component::tests::utils::{
    erc1155_mocks::CamelERC1155Mock, account_mock::SnakeAccountMock
};

fn deploy(contract_class_hash: felt252, calldata: Array<felt252>) -> ContractAddress {
    let (address, _) = starknet::deploy_syscall(
        contract_class_hash.try_into().unwrap(), 0, calldata.span(), false
    )
        .unwrap_syscall();
    address
}

fn deploy_contract() -> (ERC1155ABIDispatcher, ContractAddress) {
    let owner = setup_account();
    set_contract_address(owner);

    let calldata = array![owner.into(), 1025, 0, 5, 0];

    let address = deploy(CamelERC1155Mock::TEST_CLASS_HASH, calldata);

    (ERC1155ABIDispatcher { contract_address: address }, owner)
}

fn setup_account() -> ContractAddress {
    let mut calldata = array!['PUBKEY'];
    deploy(SnakeAccountMock::TEST_CLASS_HASH, calldata)
}
