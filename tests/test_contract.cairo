use life_source::erc20::IERC20DispatcherTrait;
use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use life_source::{ILifeSourceManagerDispatcher, ILifeSourceManagerDispatcherTrait};
use life_source::erc20::IERC20Dispatcher;
use starknet::ContractAddress;

#[test]
fn lifesource_manager_is_token_owner() {
    let erc20_contract = declare("ERC20").unwrap().contract_class();
    let mut constructor_calldata = ArrayTrait::new();
    erc20_contract.class_hash.serialize(ref constructor_calldata);
    let contract = declare("LifeSourceManager").unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();

    let dispatcher = ILifeSourceManagerDispatcher { contract_address };
    let erc_instance = IERC20Dispatcher { contract_address: dispatcher.token_address() };
    assert(erc_instance.owner() == contract_address, 'invalid owner');
    assert(erc_instance.name() == "LifeSourceToken", 'invalid name');
    assert(erc_instance.symbol() == "LFT", 'invalid symbol');
    assert(erc_instance.decimals() == 18, 'invalid decimals');
}

#[test]
fn test_admin_is_constructor_caller() {
    let erc20_contract = declare("ERC20").unwrap().contract_class();
    let mut constructor_calldata = ArrayTrait::new();
    erc20_contract.class_hash.serialize(ref constructor_calldata);
    let contract = declare("LifeSourceManager").unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();

    let dispatcher = ILifeSourceManagerDispatcher { contract_address };
    let user: ContractAddress = starknet::contract_address_const::<'USER'>();
    start_cheat_caller_address(contract_address, user);
    let admin = dispatcher.get_admin();
    stop_cheat_caller_address(contract_address);
    assert(admin == user, 'Invalid admin');
}

#[test]
fn test_add_point_from_weight() {
    let erc20_contract = declare("ERC20").unwrap().contract_class();
    let mut constructor_calldata = ArrayTrait::new();
    erc20_contract.class_hash.serialize(ref constructor_calldata);
    let contract = declare("LifeSourceManager").unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();

    let dispatcher = ILifeSourceManagerDispatcher { contract_address };
    let user: ContractAddress = starknet::contract_address_const::<'USER'>();
    start_cheat_caller_address(contract_address, user);
    dispatcher.add_point_from_weight(100);
    let user_ponts = dispatcher.get_user_points(user);
    stop_cheat_caller_address(contract_address);
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
    let erc_instance = IERC20Dispatcher { contract_address: dispatcher.token_address() };
    let user: ContractAddress = starknet::contract_address_const::<'USER'>();
    start_cheat_caller_address(contract_address, user);
    dispatcher.add_point_from_weight(100);

    dispatcher.redeem_code(100);
    let balance_of_user = erc_instance.balance_of(user);
    let user_ponts = dispatcher.get_user_points(user);
    stop_cheat_caller_address(contract_address);
    assert(balance_of_user == 100000000000000000000, 'balance wrongly set');
    assert(user_ponts == 3400, 'Invalid points');
}

