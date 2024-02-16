use core::num::traits::zero::Zero;
use core::array::SpanTrait;
use core::array::ArrayTrait;
use erc1155_component::erc1155::ERC1155Component;
use erc1155_component::interface::{IERC1155, IERC1155Dispatcher, IERC1155DispatcherTrait};
use core::traits::{Into, TryInto};
use core::debug::PrintTrait;
use erc1155_component::constants::{
    Balance, SINGLE_RAW_BALANCE_MAX_VALUE, ASSET_VARIANTS_LEN, ASSETS_TYPES_LEN
};

//
// Encoding functions
// 

// Converts an array of Balance into a raw_balances_data array
fn encode_balances(mut balances: Span<Balance>) -> Span<felt252> {
    let mut raw_balances_data: Array<felt252> = Default::default();
    let mut i = 0;
    let mut balance_batch: Array<Balance> = Default::default();
    loop {
        if i == 10 || balances.is_empty() {
            let raw_balance_data = to_felt(balance_batch.span());
            raw_balances_data.append(raw_balance_data);

            if balances.is_empty() {
                break;
            }
            balance_batch = Default::default();
            i = 0;
        }
        let data = balances.pop_front().unwrap();
        balance_batch.append(*data);
        i += 1;
    };
    raw_balances_data.span()
}

fn to_felt(mut balance_batch: Span<Balance>) -> felt252 {
    let mut low_arr: Array<Balance> = Default::default();
    let mut high_arr: Array<Balance> = Default::default();
    let mut i: usize = 0;

    // low 
    loop {
        if i == 5 || balance_batch.is_empty() {
            break;
        }
        let data = balance_batch.pop_front().unwrap();
        low_arr.append(*data);
        i += 1;
    };
    let low = to_u128(low_arr.span());

    // high
    loop {
        if balance_batch.is_empty() {
            break;
        }
        let data = balance_batch.pop_front().unwrap();
        high_arr.append(*data);
    };
    let high = to_u128(high_arr.span());

    let res: u256 = u256 { low, high };
    return res.try_into().unwrap();
}

// Recursive function to process an array of single_balance_data into a u128 
// data needs to be computed in reverse order to match the decoding function
// fixed_span must have a length of max 5
fn to_u128(mut balance_data: Span<Balance>) -> u128 {
    if balance_data.is_empty() {
        Default::default()
    } else {
        let data = balance_data.pop_front().unwrap();
        let res = to_u128(balance_data);
        res * SINGLE_RAW_BALANCE_MAX_VALUE + rawify(*data)
    }
}

fn rawify(single_data: Balance) -> u128 {
    single_data.asset_id
        + ASSETS_TYPES_LEN * (single_data.variant_id + ASSET_VARIANTS_LEN * single_data.balance)
}

