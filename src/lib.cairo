pub mod erc20;
use starknet::ContractAddress;
use core::serde::Serde;
use pragma_lib::types::{AggregationMode, DataType};
#[starknet::interface]
pub trait ILifeSourceManager<TContractState> {
    /// Add points from the weight of the waste.
    fn add_point_from_weight(ref self: TContractState, weight_in_grams: u256);
    /// Redeem code.
    fn redeem_code(ref self: TContractState, points_to_redeem: u256);
    /// Get the price of a token.
    fn get_token_price(
        self: @TContractState, oracle_address: ContractAddress, asset: DataType,
    ) -> u128;
    /// Get user points.
    fn get_user_points(self: @TContractState, user: ContractAddress) -> u256;
    /// Get the token address.
    fn token_address(self: @TContractState) -> ContractAddress;
    /// Donate to foundation.
    fn donate_to_foundation(
        self: @TContractState, token: ContractAddress, amount_in_usd: u256,
    ) -> bool;
}


/// Contract for managing user points and redeeming them as tokens.
#[starknet::contract]
mod LifeSourceManager {
    use core::num::traits::Pow;
    use starknet::storage::{
        StoragePointerReadAccess, StoragePointerWriteAccess, Map, StorageMapWriteAccess,
        StoragePathEntry,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address, ClassHash};
    use starknet::syscalls::deploy_syscall;
    use super::ILifeSourceManager;
    use pragma_lib::abi::{IPragmaABIDispatcher, IPragmaABIDispatcherTrait};
    use pragma_lib::types::{PragmaPricesResponse};
    use starknet::contract_address::contract_address_const;
    use crate::{erc20::IERC20Dispatcher, erc20::IERC20DispatcherTrait};
    use pragma_lib::types::{AggregationMode, DataType};

    #[storage]
    struct Storage {
        price_oracles: Map<
            ContractAddress, ContractAddress,
        >, // Mapping from token address to oracle address.
        user_points: Map<ContractAddress, PointData>, // Mapping from user address to PointData.
        token_address: ContractAddress // Address of the ERC20 token contract.,
    }


    /// Struct representing user point data.
    #[derive(Drop, Serde, Copy, starknet::Store)]
    struct PointData {
        points: u256,
        updated_timestamp: u256,
        created_timestamp: u256,
    }

    /// Errors
    pub mod Errors {
        pub const LifeSourceManager_WEIGHT_NON_ZERO: felt252 = 'Weight must be non-zero';
        pub const LifeSourceManager_USER_HAVE_NO_POINT: felt252 = 'User has no points';
        pub const LifeSourceManager_INSUFFICIENT_POINTS: felt252 = 'Insufficient points';
        pub const LifeSourceManager_NO_ORACLE_FOR_TOKEN: felt252 = 'No oracle for token';
        pub const LifeSourceManager_INVALID_PRICE_RETURNED: felt252 = 'Invalid price returned';
    }

    /// Events
    #[event]
    #[derive(Copy, Drop, Debug, PartialEq, starknet::Event)]
    // The event enum must be annotated with the `#[event]` attribute.
    // It must also derive at least the `Drop` and `starknet::Event` traits.
    pub enum Event {
        AddPointFromWeight: AddPointFromWeight,
        RedeemCode: RedeemCode,
    }

    #[derive(Copy, Drop, Debug, PartialEq, starknet::Event)]
    pub struct AddPointFromWeight {
        pub points_to_add: u256,
        pub user: ContractAddress,
    }
    #[derive(Copy, Drop, Debug, PartialEq, starknet::Event)]
    pub struct RedeemCode {
        pub points_to_redeem: u256,
        pub user: ContractAddress,
    }

    const POINT_BASIS: u256 = 35;


    #[constructor]
    fn constructor(ref self: ContractState, class_hash: ClassHash) {
        let salt = 0;
        let unique = false;
        let mut calldata = array![];
        let (contract_address, _) = deploy_syscall(class_hash, salt, calldata.span(), unique)
            .unwrap();
        self.token_address.write(contract_address);
        // self.price_oracles.entry(self.get_strk_address()).write(); // oracle for STRK/USD
    // self.price_oracles.entry(self.get_eth_address()).write(); // oracle for ETH/USD
    }


    #[abi(embed_v0)]
    impl LifeSourceManagerImpl of ILifeSourceManager<ContractState> {
        fn add_point_from_weight(ref self: ContractState, weight_in_grams: u256) {
            let user = get_caller_address();
            let points_to_add = weight_in_grams * POINT_BASIS;
            assert(points_to_add != 0, Errors::LifeSourceManager_WEIGHT_NON_ZERO);
            // Fetch existing PointData or initialize a new one.
            let mut point_data = self.user_points.entry(user).read();

            // Update points and timestamps.
            point_data.points = point_data.points + points_to_add;
            point_data.updated_timestamp = get_block_timestamp().try_into().unwrap();

            self.user_points.write(user, point_data);

            self.emit(Event::AddPointFromWeight(AddPointFromWeight { user, points_to_add }));
        }

        /// Function to redeem points for tokens.
        fn redeem_code(ref self: ContractState, points_to_redeem: u256) {
            let user = get_caller_address();
            // Fetch user data.
            let mut point_data = self.user_points.entry(user).read();

            // Check sufficient points.
            assert(
                point_data.points >= points_to_redeem,
                Errors::LifeSourceManager_INSUFFICIENT_POINTS,
            );

            // Deduct points and update storage.
            point_data.points = point_data.points - points_to_redeem;
            self.user_points.write(user, point_data);

            let amount_to_mint = points_to_redeem
                * 10.pow(18).try_into().unwrap(); // Assume 18 decimals.

            IERC20Dispatcher { contract_address: self.token_address.read() }
                .mint(user, amount_to_mint);
            self.emit(Event::RedeemCode(RedeemCode { user, points_to_redeem }));
        }

        fn donate_to_foundation(
            self: @ContractState, token: ContractAddress, amount_in_usd: u256,
        ) -> bool {
            const KEY: felt252 = 'STRK/USD';
            let oracle_address: ContractAddress = contract_address_const::<
                0x06df335982dddce41008e4c03f2546fa27276567b5274c7d0c1262f3c2b5d167,
            >();
            let price = self.get_token_price(oracle_address, DataType::SpotEntry(KEY));
            true
        }

        fn get_token_price(
            self: @ContractState, oracle_address: ContractAddress, asset: DataType,
        ) -> u128 {
            let oracle_dispatcher = IPragmaABIDispatcher { contract_address: oracle_address };
            let output: PragmaPricesResponse = oracle_dispatcher
                .get_data(asset, AggregationMode::Median(()));
            return output.price;
        }

        fn get_user_points(self: @ContractState, user: ContractAddress) -> u256 {
            let point_data = self.user_points.entry(user).read();
            point_data.points
        }

        fn token_address(self: @ContractState) -> ContractAddress {
            self.token_address.read()
        }
    }

    #[generate_trait]
    impl Private of PrivateTrait {
        fn get_strk_address(self: @ContractState) -> ContractAddress {
            contract_address_const::<
                0x4718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d,
            >()
        }
        fn get_eth_address(self: @ContractState) -> ContractAddress {
            contract_address_const::<
                0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7,
            >()
        }
    }
}
