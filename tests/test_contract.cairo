use snforge_std::{declare, ContractClassTrait, DeclareResultTrait};
use my_project::{ILifeSourceManagerDispatcher, ILifeSourceManagerDispatcherTrait};


#[test]
fn test_add_point_from_weight() {
    let erc20_contract = declare("ERC20").unwrap().contract_class();
    let mut constructor_calldata = ArrayTrait::new();
    erc20_contract.class_hash.serialize(ref constructor_calldata);
    let contract = declare("LifeSourceManager").unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();

    let dispatcher = ILifeSourceManagerDispatcher { contract_address };
    dispatcher.add_point_from_weight(42);

    let user_ponts = dispatcher.get_user_points();

    assert(user_ponts == 3500, 'Invalid points');
}
#[test]
fn redeem_code() {
    let erc20_contract = declare("ERC20").unwrap().contract_class();
    let mut constructor_calldata = ArrayTrait::new();
    erc20_contract.class_hash.serialize(ref constructor_calldata);
    let contract = declare("LifeSourceManager").unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();

    let dispatcher = ILifeSourceManagerDispatcher { contract_address };

    dispatcher.add_point_from_weight(42);

    let user_ponts = dispatcher.get_user_points();

    assert(user_ponts == 3500, 'Invalid points');
}

