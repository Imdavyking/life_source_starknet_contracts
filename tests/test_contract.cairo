use starknet::ContractAddress;

use snforge_std::{declare, ContractClassTrait, DeclareResultTrait};
use my_project::{ILifeSourceManagerDispatcher, ILifeSourceManagerDispatcherTrait};

fn deploy_contract(name: ByteArray) -> ContractAddress {
    let contract = declare(name).unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@ArrayTrait::new()).unwrap();
    contract_address
}

#[test]
fn test_add_point_from_weight() {
    let contract_address = deploy_contract("LifeSourceManager");

    let dispatcher = ILifeSourceManagerDispatcher { contract_address };

    // dispatcher.add_point_from_weight(42);

    // let user_ponts = dispatcher.get_user_points();

    // assert(user_ponts == 3500, 'Invalid points');
}

// #[test]
// fn redeem_code() {
//     let contract_address = deploy_contract("LifeSourceManager");

//     let dispatcher = ILifeSourceManagerDispatcher { contract_address };

//     dispatcher.add_point_from_weight(42);

//     let user_ponts = dispatcher.get_user_points();

//     assert(user_ponts == 3500, 'Invalid points');
// }
