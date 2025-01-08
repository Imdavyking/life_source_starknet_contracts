use starknet::ContractAddress;
pub mod erc20;
#[starknet::interface]
pub trait ILifeSourceManager<TContractState> {
    /// Add points from the weight of the waste.
    fn add_point_from_weight(ref self: TContractState, weight_in_grams: u256);
    /// Redeem code.
    fn redeem_code(ref self: TContractState, points_to_redeem: u256);
    /// Get the price of a token.
    fn get_token_price(self: @TContractState, token: ContractAddress) -> u256;
    /// Get user points.
    fn get_user_points(self: @TContractState) -> u256;
}


/// Contract for managing user points and redeeming them as tokens.
#[starknet::contract]
mod LifeSourceManager {
    use core::num::traits::Pow;
    use starknet::storage::StorageMapWriteAccess;
    use starknet::storage::StoragePathEntry;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess, Map};
    use starknet::{
        ContractAddress, get_block_timestamp, get_caller_address, contract_address_const,
    };
    use super::ILifeSourceManager;
    use pragma_lib::abi::{IPragmaABIDispatcher, IPragmaABIDispatcherTrait};
    use pragma_lib::types::{DataType, PragmaPricesResponse};
    use erc20::IERC20Dispatcher;

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
    fn constructor(ref self: ContractState, token_address: ContractAddress) {
        self.token_address.write(token_address);
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

        fn get_token_price(self: @ContractState, token: ContractAddress) -> u256 {
            let oracle = self.price_oracles.entry(token).read();
            assert(oracle != contract_address_const::<0>(), 'no oracle for token');
            let asset_id = 0;

            // Create oracle dispatcher and get price
            let oracle_dispatcher = IPragmaABIDispatcher {
                contract_address: self.price_oracles.entry(token).read(),
            };
            let output: PragmaPricesResponse = oracle_dispatcher
                .get_data_median(DataType::SpotEntry(asset_id));
            assert(output.price > 0, 'invalid price returned');

            let price: u256 = (output.price).try_into().unwrap();
            price
        }

        fn get_user_points(self: @ContractState) -> u256 {
            let user = get_caller_address();
            let point_data = self.user_points.entry(user).read();
            point_data.points
        }
    }
}
