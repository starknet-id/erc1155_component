#[starknet::component]
mod ERC1155Component {
    use core::num::traits::zero::Zero;
    use openzeppelin::account;
    use openzeppelin::introspection::dual_src5::{DualCaseSRC5, DualCaseSRC5Trait};
    use openzeppelin::introspection::src5::SRC5Component::InternalTrait as SRC5InternalTrait;
    use openzeppelin::introspection::src5::SRC5Component;
    use erc1155_component::dual1155_receiver::{
        DualCaseERC1155Receiver, DualCaseERC1155ReceiverTrait
    };
    use erc1155_component::interface;
    use starknet::ContractAddress;
    use starknet::get_caller_address;
    use core::byte_array::ByteArray;

    use erc1155_component::{encode, decode};

    #[storage]
    struct Storage {
        ERC1155_balances: LegacyMap<(u256, ContractAddress), u256>,
        ERC1155_operator_approvals: LegacyMap<(ContractAddress, ContractAddress), bool>,
        ERC1155_uri: felt252,
        raw_balances_data: LegacyMap<(ContractAddress, felt252), felt252>
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        TransferSingle: TransferSingle,
        TransferBatch: TransferBatch,
        ApprovalForAll: ApprovalForAll,
        URI: URI
    }

    /// Emitted when `value` token is transferred from `from` to `to` for `id`.
    #[derive(Drop, starknet::Event)]
    struct TransferSingle {
        #[key]
        operator: ContractAddress,
        #[key]
        from: ContractAddress,
        #[key]
        to: ContractAddress,
        id: u256,
        value: u256
    }

    /// Emitted when `values` are transferred from `from` to `to` for `ids`.
    #[derive(Drop, starknet::Event)]
    struct TransferBatch {
        #[key]
        operator: ContractAddress,
        #[key]
        from: ContractAddress,
        #[key]
        to: ContractAddress,
        ids: Span<u256>,
        values: Span<u256>,
    }

    /// Emitted when `account` enables or disables (`approved`) `operator` to manage
    /// all of its assets.
    #[derive(Drop, starknet::Event)]
    struct ApprovalForAll {
        #[key]
        account: ContractAddress,
        #[key]
        operator: ContractAddress,
        approved: bool
    }

    /// Emitted when the URI for token type `id` changes to `value`, if it is a non-programmatic URI.
    ///
    /// If an `URI` event was emitted for `id`, the standard
    /// https://eips.ethereum.org/EIPS/eip-1155#metadata-extensions[guarantees] that `value` will equal the value
    /// returned by `IERC1155MetadataURI::uri`.
    #[derive(Drop, starknet::Event)]
    struct URI {
        #[key]
        id: u256,
        value: ByteArray
    }

    mod Errors {
        const INVALID_ACCOUNT: felt252 = 'ERC1155: invalid account';
        const INVALID_OPERATOR: felt252 = 'ERC1155: invalid operator';
        const UNAUTHORIZED: felt252 = 'ERC1155: unauthorized caller';
        const SELF_APPROVAL: felt252 = 'ERC1155: self approval';
        const INVALID_RECEIVER: felt252 = 'ERC1155: invalid receiver';
        const INVALID_SENDER: felt252 = 'ERC1155: wrong sender';
        const INVALID_ARRAY_LENGTH: felt252 = 'ERC1155: no equal array length';
        const INSUFFICIENT_BALANCE: felt252 = 'ERC1155: insufficient balance';
    }

    //
    // External
    //

    #[embeddable_as(ERC1155Impl)]
    impl ERC1155<
        TContractState,
        +HasComponent<TContractState>,
        +SRC5Component::HasComponent<TContractState>,
        +Drop<TContractState>
    > of interface::IERC1155<ComponentState<TContractState>> {
        /// Returns the number of NFTs owned by `account` for a specific `token_id`.
        fn balance_of(
            self: @ComponentState<TContractState>, account: ContractAddress, token_id: u256
        ) -> u256 {
            // self.ERC1155_balances.read((token_id, account))
            self._balance_of(account, token_id.try_into().unwrap())
        }

        /// Returns a span of u256 values representing the batch balances of the
        /// `accounts` for the specified `token_ids`.
        ///
        /// Requirements:
        ///
        /// - `token_ids` and `accounts` must have the same length.
        fn balance_of_batch(
            self: @ComponentState<TContractState>,
            accounts: Span<ContractAddress>,
            token_ids: Span<u256>
        ) -> Span<u256> {
            assert(accounts.len() == token_ids.len(), Errors::INVALID_ARRAY_LENGTH);

            let mut batch_balances = array![];
            let mut index = 0;
            loop {
                if index == token_ids.len() {
                    break;
                }
                batch_balances.append(self.balance_of(*accounts.at(index), *token_ids.at(index)));
                index += 1;
            };

            batch_balances.span()
        }

        /// Transfers ownership of `token_id` from `from` if `to` is either an account or `IERC1155Receiver`.
        ///
        /// `data` is additional data, it has no specified format and it is passed to `to`.
        ///
        /// WARNING: This function can potentially allow a reentrancy attack when transferring tokens
        /// to an untrusted contract, when invoking `on_ERC1155_received` on the receiver.
        /// Ensure to follow the checks-effects-interactions pattern and consider employing
        /// reentrancy guards when interacting with untrusted contracts.
        ///
        /// Requirements:
        ///
        /// - Caller is either approved or the `token_id` owner.
        /// - `from` is not the zero address.
        /// - `to` is not the zero address.
        /// - If `to` refers to a non-account contract, it must implement `IERC1155Receiver::on_ERC1155_received`
        ///   and return the required magic value.
        ///
        /// Emits a `TransferSingle` event.
        fn safe_transfer_from(
            ref self: ComponentState<TContractState>,
            from: ContractAddress,
            to: ContractAddress,
            token_id: u256,
            value: u256,
            data: Span<felt252>
        ) {
            let token_ids = array![token_id].span();
            let values = array![value].span();
            self.safe_batch_transfer_from(from, to, token_ids, values, data)
        }

        /// Batched version of `safeTransferFrom`.
        ///
        /// WARNING: This function can potentially allow a reentrancy attack when transferring tokens
        /// to an untrusted contract, when invoking `on_ERC1155_batch_received` on the receiver.
        /// Ensure to follow the checks-effects-interactions pattern and consider employing
        /// reentrancy guards when interacting with untrusted contracts.
        ///
        /// Requirements:
        ///
        /// - Caller is either approved or the `token_id` owner.
        /// - `from` is not the zero address.
        /// - `to` is not the zero address.
        /// - `token_ids` and `values` must have the same length.
        /// - If `to` refers to a non-account contract, it must implement `IERC1155Receiver::on_ERC1155_batch_received`
        ///   and return the acceptance magic value.
        ///
        /// Emits either a `TransferSingle` or a `TransferBatch` event, depending on the length of the array arguments.
        fn safe_batch_transfer_from(
            ref self: ComponentState<TContractState>,
            from: starknet::ContractAddress,
            to: starknet::ContractAddress,
            token_ids: Span<u256>,
            values: Span<u256>,
            data: Span<felt252>
        ) {
            assert(from.is_non_zero(), Errors::INVALID_SENDER);
            assert(to.is_non_zero(), Errors::INVALID_RECEIVER);

            let operator = get_caller_address();
            if from != operator {
                assert(self.is_approved_for_all(from, operator), Errors::UNAUTHORIZED);
            }

            self.update_with_acceptance_check(from, to, token_ids, values, data);
        }

        /// Enable or disable approval for `operator` to manage all of the
        /// callers assets.
        ///
        /// Requirements:
        ///
        /// - `operator` cannot be the caller.
        /// - `operator` cannot be the zero address.
        ///
        /// Emits an `ApprovalForAll` event.
        fn set_approval_for_all(
            ref self: ComponentState<TContractState>, operator: ContractAddress, approved: bool
        ) {
            let owner = get_caller_address();
            assert(owner != operator, Errors::SELF_APPROVAL);
            assert(operator.is_non_zero(), Errors::INVALID_OPERATOR);

            self.ERC1155_operator_approvals.write((owner, operator), approved);
            self.emit(ApprovalForAll { account: owner, operator, approved });
        }

        /// Query if `operator` is an authorized operator for `owner`.
        fn is_approved_for_all(
            self: @ComponentState<TContractState>, owner: ContractAddress, operator: ContractAddress
        ) -> bool {
            self.ERC1155_operator_approvals.read((owner, operator))
        }
    }

    #[embeddable_as(ERC1155MetadataURIImpl)]
    impl ERC1155MetadataURI<
        TContractState,
        +HasComponent<TContractState>,
        +SRC5Component::HasComponent<TContractState>,
        +Drop<TContractState>
    > of interface::IERC1155MetadataURI<ComponentState<TContractState>> {
        /// This implementation returns the same URI for *all* token types. It relies
        /// on the token type ID substitution mechanism defined in the EIP:
        /// https://eips.ethereum.org/EIPS/eip-1155#metadata.
        ///
        /// Clients calling this function must replace the `\{id\}` substring with the
        /// actual token type ID.
        fn uri(self: @ComponentState<TContractState>, token_id: u256) -> felt252 {
            self.ERC1155_uri.read()
        }
    }

    /// Adds camelCase support for `IERC1155`.
    #[embeddable_as(ERC1155CamelImpl)]
    impl ERC1155Camel<
        TContractState,
        +HasComponent<TContractState>,
        +SRC5Component::HasComponent<TContractState>,
        +Drop<TContractState>
    > of interface::IERC1155CamelOnly<ComponentState<TContractState>> {
        fn balanceOf(
            self: @ComponentState<TContractState>, account: ContractAddress, tokenId: u256
        ) -> u256 {
            self.balance_of(account, tokenId)
        }

        fn balanceOfBatch(
            self: @ComponentState<TContractState>,
            accounts: Span<ContractAddress>,
            tokenIds: Span<u256>
        ) -> Span<u256> {
            self.balance_of_batch(accounts, tokenIds)
        }

        fn safeTransferFrom(
            ref self: ComponentState<TContractState>,
            from: ContractAddress,
            to: ContractAddress,
            tokenId: u256,
            value: u256,
            data: Span<felt252>
        ) {
            self.safe_transfer_from(from, to, tokenId, value, data)
        }

        fn safeBatchTransferFrom(
            ref self: ComponentState<TContractState>,
            from: ContractAddress,
            to: ContractAddress,
            tokenIds: Span<u256>,
            values: Span<u256>,
            data: Span<felt252>
        ) {
            self.safe_batch_transfer_from(from, to, tokenIds, values, data)
        }

        fn setApprovalForAll(
            ref self: ComponentState<TContractState>, operator: ContractAddress, approved: bool
        ) {
            self.set_approval_for_all(operator, approved)
        }

        fn isApprovedForAll(
            self: @ComponentState<TContractState>, owner: ContractAddress, operator: ContractAddress
        ) -> bool {
            self.is_approved_for_all(owner, operator)
        }
    }

    //
    // Internal
    //

    #[generate_trait]
    impl InternalImpl<
        TContractState,
        +HasComponent<TContractState>,
        impl SRC5: SRC5Component::HasComponent<TContractState>,
        +Drop<TContractState>
    > of InternalTrait<TContractState> {
        /// Initializes the contract by setting the token uri.
        /// This should only be used inside the contract's constructor.
        fn initializer(ref self: ComponentState<TContractState>, uri: felt252) {
            self.ERC1155_uri.write(uri);

            let mut src5_component = get_dep_component_mut!(ref self, SRC5);
            src5_component.register_interface(interface::IERC1155_ID);
            src5_component.register_interface(interface::IERC1155_METADATA_ID);
        }

        /// Transfers a `value` amount of tokens of type `id` from `from` to `to`.
        /// Will mint (or burn) if `from` (or `to`) is the zero address.
        ///
        /// Requirements:
        ///
        /// - `token_ids` and `values` must have the same length.
        ///
        /// Emits a `TransferSingle` event if the arrays contain one element, and `TransferBatch` otherwise.
        ///
        /// NOTE: The ERC-1155 acceptance check is not performed in this function.
        /// See `update_with_acceptance_check` instead.
        fn update(
            ref self: ComponentState<TContractState>,
            from: ContractAddress,
            to: ContractAddress,
            token_ids: Span<u256>,
            values: Span<u256>
        ) {
            assert(token_ids.len() == values.len(), Errors::INVALID_ARRAY_LENGTH);

            let mut index = 0;
            loop {
                if index == token_ids.len() {
                    break;
                }
                let token_id = *token_ids.at(index);
                let value = *values.at(index);
                if from.is_non_zero() {
                    let from_balance = self.ERC1155_balances.read((token_id, from));
                    // let from_balance = self._balance_of(from, token_id.try_into().unwrap());
                    assert(from_balance >= value, Errors::INSUFFICIENT_BALANCE);
                    self.ERC1155_balances.write((token_id, from), from_balance - value);
                }
                if to.is_non_zero() {
                    let to_balance = self.ERC1155_balances.read((token_id, to));
                    self.ERC1155_balances.write((token_id, to), to_balance + value);
                }
                index += 1;
            };

            let operator = get_caller_address();
            if token_ids.len() == 1 {
                self
                    .emit(
                        TransferSingle {
                            operator, from, to, id: *token_ids.at(0), value: *values.at(0)
                        }
                    );
            } else {
                self.emit(TransferBatch { operator, from, to, ids: token_ids, values });
            }
        }

        /// Version of `update` that performs the token acceptance check by calling
        /// `IERC1155Receiver-onERC1155Received` or `IERC1155Receiver-onERC1155BatchReceived` if
        /// the receiver is not reconized as an account.
        ///
        /// Requirements:
        ///
        /// - `to` is either an account contract or supports the `IERC1155Receiver` interface.
        /// - `token_ids` and `values` must have the same length.
        fn update_with_acceptance_check(
            ref self: ComponentState<TContractState>,
            from: ContractAddress,
            to: ContractAddress,
            token_ids: Span<u256>,
            values: Span<u256>,
            data: Span<felt252>
        ) {
            self.update(from, to, token_ids, values);
            if token_ids.len() == 1 {
                _check_on_ERC1155_received(from, to, *token_ids.at(0), *values.at(0), data);
            } else {
                _check_on_ERC1155_batch_received(from, to, token_ids, values, data);
            }
        }

        /// Creates a `value` amount of tokens of type `token_id`, and assigns them to `to`.
        ///
        /// Requirements:
        ///
        /// - `to` cannot be the zero address.
        /// - If `to` refers to a smart contract, it must implement `IERC1155Receiver::on_ERC1155_received`
        /// and return the acceptance magic value.
        ///
        /// Emits a `TransferSingle` event.
        fn mint_with_acceptance_check(
            ref self: ComponentState<TContractState>,
            to: ContractAddress,
            token_id: u256,
            value: u256,
            data: Span<felt252>
        ) {
            assert(to.is_non_zero(), Errors::INVALID_RECEIVER);

            let token_ids = array![token_id].span();
            let values = array![value].span();
            self
                .update_with_acceptance_check(
                    core::zeroable::Zeroable::zero(), to, token_ids, values, data
                );
        }

        /// Batched version of `mint_with_acceptance_check`.
        ///
        /// Requirements:
        ///
        /// - `to` cannot be the zero address.
        /// - `token_ids` and `values` must have the same length.
        /// - If `to` refers to a smart contract, it must implement `IERC1155Receiver::on_ERC1155_batch_received`
        /// and return the acceptance magic value.
        ///
        /// Emits a `TransferBatch` event.
        fn batch_mint_with_acceptance_check(
            ref self: ComponentState<TContractState>,
            to: ContractAddress,
            token_ids: Span<u256>,
            values: Span<u256>,
            data: Span<felt252>
        ) {
            assert(to.is_non_zero(), Errors::INVALID_RECEIVER);
            self
                .update_with_acceptance_check(
                    core::zeroable::Zeroable::zero(), to, token_ids, values, data
                );
        }

        /// Destroys a `value` amount of tokens of type `token_id` from `from`.
        ///
        /// Requirements:
        ///
        /// - `from` cannot be the zero address.
        /// - `from` must have at least `value` amount of tokens of type `token_id`.
        ///
        /// Emits a `TransferSingle` event.
        fn burn(
            ref self: ComponentState<TContractState>,
            from: ContractAddress,
            token_id: u256,
            value: u256
        ) {
            assert(from.is_non_zero(), Errors::INVALID_RECEIVER);

            let token_ids = array![token_id].span();
            let values = array![value].span();
            self
                .update_with_acceptance_check(
                    from, core::zeroable::Zeroable::zero(), token_ids, values, array![].span()
                );
        }

        /// Batched version of `burn`.
        ///
        /// Requirements:
        ///
        /// - `from` cannot be the zero address.
        /// - `from` must have at least `value` amount of tokens of type `token_id`.
        /// - `token_ids` and `values` must have the same length.
        ///
        /// Emits a `TransferBatch` event.
        fn batch_burn(
            ref self: ComponentState<TContractState>,
            from: ContractAddress,
            token_ids: Span<u256>,
            values: Span<u256>
        ) {
            assert(from.is_non_zero(), Errors::INVALID_RECEIVER);
            self
                .update_with_acceptance_check(
                    from, core::zeroable::Zeroable::zero(), token_ids, values, array![].span()
                );
        }

        // Convert asset_id and variant_id into a token_id
        fn to_token_id(asset_id: u128, variant_id: u128) -> u128 {
            asset_id * 1024_u128 + variant_id
        }

        // Convert a token_id into a asset_id and variant_id
        fn from_token_id(token_id: u128) -> (u128, u128) {
            (token_id / 1024_u128, token_id % 1024_u128)
        }

        fn get_raw_balances_data(
            self: @ComponentState<TContractState>, account: ContractAddress
        ) -> Span<felt252> {
            let mut raw_balances_data: Array<felt252> = Default::default();
            let mut i = 0;
            loop {
                let data = self.raw_balances_data.read((account, i));
                if data.is_zero() {
                    break;
                }
                raw_balances_data.append(data);
            };
            raw_balances_data.span()
        }

        // Return the balance of token_id for account
        // function will read the raw_balances_data, build a dict of balances and return the balance of token_id
        fn _balance_of(
            self: @ComponentState<TContractState>, account: ContractAddress, token_id: u128
        ) -> u256 {
            let raw_balances_data = self.get_raw_balances_data(account);
            let mut balances = decode::decode_balances(raw_balances_data);
            // let balance = balances.get(token_id.into());
            // balance.into()
            0
        }
    // todo : write balances
    }

    /// Checks if `to` either accepts the token either by implementing `IERC1155Receiver`
    /// or if it's an account contract (supporting ISRC6). The transaction will fail if both are false.
    fn _check_on_ERC1155_received(
        from: ContractAddress, to: ContractAddress, token_id: u256, value: u256, data: Span<felt252>
    ) {
        let accepted = if (DualCaseSRC5 { contract_address: to }
            .supports_interface(interface::IERC1155_RECEIVER_ID)) {
            DualCaseERC1155Receiver { contract_address: to }
                .on_erc1155_received(
                    get_caller_address(), from, token_id, value, data
                ) == interface::IERC1155_RECEIVER_ID
        } else {
            DualCaseSRC5 { contract_address: to }.supports_interface(account::interface::ISRC6_ID)
        };
        assert(accepted, Errors::INVALID_RECEIVER);
    }

    /// Checks if `to` either accepts the token either by implementing `IERC1155Receiver`
    /// or if it's an account contract (supporting ISRC6). The transaction will fail if both are false.
    fn _check_on_ERC1155_batch_received(
        from: ContractAddress,
        to: ContractAddress,
        token_ids: Span<u256>,
        values: Span<u256>,
        data: Span<felt252>
    ) {
        let accepted = if (DualCaseSRC5 { contract_address: to }
            .supports_interface(interface::IERC1155_RECEIVER_ID)) {
            DualCaseERC1155Receiver { contract_address: to }
                .on_erc1155_batch_received(
                    get_caller_address(), from, token_ids, values, data
                ) == interface::IERC1155_RECEIVER_ID
        } else {
            DualCaseSRC5 { contract_address: to }.supports_interface(account::interface::ISRC6_ID)
        };
        assert(accepted, Errors::INVALID_RECEIVER);
    }
}
