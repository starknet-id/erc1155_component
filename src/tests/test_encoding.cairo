use core::array::SpanTrait;
use starknet::testing;
use erc1155_component::{decode, encode};
use erc1155_component::constants::Balance;
use core::debug::PrintTrait;

#[test]
#[available_gas(20000000000)]
fn test_encode_balances() {
    let balances_to_encode: Array<Balance> = array![
        Balance { asset_id: 0, variant_id: 5, balance: 76 },
        Balance { asset_id: 1, variant_id: 10, balance: 39 },
        Balance { asset_id: 2, variant_id: 15, balance: 23 },
        Balance { asset_id: 3, variant_id: 20, balance: 98 },
        Balance { asset_id: 4, variant_id: 25, balance: 600 },
        Balance { asset_id: 5, variant_id: 30, balance: 329 },
        Balance { asset_id: 6, variant_id: 35, balance: 23 },
        Balance { asset_id: 7, variant_id: 40, balance: 3 },
        Balance { asset_id: 8, variant_id: 45, balance: 0 },
        Balance { asset_id: 9, variant_id: 50, balance: 1 },
        Balance { asset_id: 10, variant_id: 55, balance: 35 },
        Balance { asset_id: 11, variant_id: 60, balance: 2 },
    ];
    let mut encoded_balances = encode::encode_balances(balances_to_encode.span());

    let mut expected_balances = array![
        0x1e6e5ce7d2f5831ca5cb8e6ebe700043f5338fad6e9184881a355656f2e, 0x2b933d6c57
    ]
        .span();

    assert(encoded_balances.len() == expected_balances.len(), 'wrong len');

    loop {
        if encoded_balances.is_empty() {
            break;
        }
        let encoded_balances = encoded_balances.pop_front().unwrap();
        let expected_balance = expected_balances.pop_front().unwrap();
        assert(encoded_balances == expected_balance, 'wrong felt');
    }
}

#[test]
#[available_gas(20000000000)]
fn test_decode_balances() {
    let mut balances = decode::decode_balances(
        array![0x1e6e5ce7d2f5831ca5cb8e6ebe700043f5338fad6e9184881a355656f2e, 0x2b933d6c57].span()
    );

    let mut expected_balances: Array<Balance> = array![
        Balance { asset_id: 0, variant_id: 5, balance: 76 },
        Balance { asset_id: 1, variant_id: 10, balance: 39 },
        Balance { asset_id: 2, variant_id: 15, balance: 23 },
        Balance { asset_id: 3, variant_id: 20, balance: 98 },
        Balance { asset_id: 4, variant_id: 25, balance: 600 },
        Balance { asset_id: 5, variant_id: 30, balance: 329 },
        Balance { asset_id: 6, variant_id: 35, balance: 23 },
        Balance { asset_id: 7, variant_id: 40, balance: 3 },
        Balance { asset_id: 8, variant_id: 45, balance: 0 },
        Balance { asset_id: 9, variant_id: 50, balance: 1 },
        Balance { asset_id: 10, variant_id: 55, balance: 35 },
        Balance { asset_id: 11, variant_id: 60, balance: 2 },
    ];

    assert(balances.len() == expected_balances.len(), 'wrong len');

    loop {
        if balances.is_empty() {
            break;
        }
        let decoded_balance = balances.pop_front().unwrap();
        let expected_balance = expected_balances.pop_front().unwrap();
        assert(*decoded_balance.asset_id == expected_balance.asset_id, 'wrong asset_id');
        assert(*decoded_balance.variant_id == expected_balance.variant_id, 'wrong_variant_id');
        assert(*decoded_balance.balance == expected_balance.balance, 'wrong balance amount');
    }
}
