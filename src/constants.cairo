const ASSETS_TYPES_LEN: u128 = 12;
const ASSET_VARIANTS_LEN: u128 = 1024;
const SINGLE_RAW_BALANCE_MAX_VALUE: u128 = 7395323;

#[derive(Drop, Copy)]
struct Balance {
    asset_id: u128,
    variant_id: u128,
    balance: u128
}
