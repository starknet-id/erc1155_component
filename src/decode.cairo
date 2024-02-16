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
// Decoding functions
// 

// Decode a raw_balances_data into an array of Balance
fn decode_balances(raw_balances_data: Span<felt252>) -> Array<Balance> {
    let mut balances: Array<Balance> = Default::default();
    // let mut balances: Felt252Dict<u128> = Default::default();

    let mut single_balance_data = get_single_raw_balance_data(raw_balances_data);
    loop {
        match single_balance_data.pop_front() {
            Option::Some(raw_single_data) => {
                let balance = process(*raw_single_data);
                // we use a dict to store the balance data from token_id to balance
                // balances.insert((balance.asset_id * 1024 + balance.variant_id).into(), balance.balance);
                'asset'.print();
                balance.asset_id.print();
                balance.variant_id.print();
                balance.balance.print();
                balances.append(balance);
            },
            Option::None => { break; }
        }
    };
    balances
}

// Convert an array of raw_balances_data into an array of single raw balance data
fn get_single_raw_balance_data(mut raw_balances_data: Span<felt252>) -> Span<u128> {
    let mut raw_arr: Array<u128> = Default::default();
    let single_raw_balance_max_value: NonZero<u128> = SINGLE_RAW_BALANCE_MAX_VALUE
        .try_into()
        .unwrap();
    loop {
        match raw_balances_data.pop_front() {
            Option::Some(data) => {
                let data_u256: u256 = (*data).into();
                let mut low = data_u256.low;
                let mut high = data_u256.high;
                loop {
                    if low.is_zero() {
                        break;
                    }
                    let (new_low, raw) = DivRem::<u128>::div_rem(low, single_raw_balance_max_value);
                    raw_arr.append(raw);
                    low = new_low;
                };
                loop {
                    if high.is_zero() {
                        break;
                    }
                    let (new_high, raw) = DivRem::<
                        u128
                    >::div_rem(high, single_raw_balance_max_value);
                    raw_arr.append(raw);
                    high = new_high;
                };
            },
            Option::None => { break; }
        }
    };
    raw_arr.span()
}

// convert a raw_single_data into a asset_id, variant_id, balance
fn process(raw_single_data: u128) -> Balance {
    let asset_divider: NonZero<u128> = ASSETS_TYPES_LEN.try_into().unwrap();
    let variant_divider: NonZero<u128> = ASSET_VARIANTS_LEN.try_into().unwrap();

    let (q, asset_id) = DivRem::<u128>::div_rem(raw_single_data, asset_divider);
    let (balance, variant_id) = DivRem::<u128>::div_rem(q, variant_divider);

    return Balance { asset_id, variant_id, balance };
}

