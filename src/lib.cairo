pub mod erc20;
use starknet::ContractAddress;
use pragma_lib::types::DataType;
#[starknet::interface]
pub trait ILifeSourceManager<TContractState> {
    /// Add points from the weight of the waste.
    fn add_point_from_weight(ref self: TContractState, weight_in_grams: u256);
    /// Redeem code.
    fn redeem_code(ref self: TContractState, points_to_redeem: u256);
    /// Get the price of a token.
    fn get_token_price(
        self: @TContractState, oracle_address: ContractAddress, asset: DataType,
    ) -> (u128, u32);
    /// Get user points.
    fn get_user_points(self: @TContractState, user: ContractAddress) -> u256;
    /// Get the token address.
    fn token_address(self: @TContractState) -> ContractAddress;
    /// Donate to foundation.
    fn donate_to_foundation(
        ref self: TContractState, token: ContractAddress, amount_in_usd: u256,
    ) -> bool;
    /// Get usd to token price.
    fn get_usd_to_token_price(
        ref self: TContractState, token: ContractAddress, amount_in_usd: u256,
    ) -> u256;
    /// Withdraw donation.
    fn withdraw_donation(ref self: TContractState, token: ContractAddress, amount: u256) -> bool;
    /// Get donation
    fn get_donation(self: @TContractState, token: ContractAddress) -> u256;
    /// Change admin.
    fn change_admin(ref self: TContractState, new_admin: ContractAddress);
}


/// Contract for managing user points and redeeming them as tokens.
#[starknet::contract]
mod LifeSourceManager {
    use core::num::traits::OverflowingMul;
    use core::num::traits::Pow;
    use starknet::storage::StoragePathEntry;
    use starknet::storage::{
        StoragePointerReadAccess, StoragePointerWriteAccess, Map, StorageMapWriteAccess,
    };
    use starknet::{
        ContractAddress, get_block_timestamp, get_caller_address, get_contract_address, ClassHash,
        get_tx_info,
    };
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
            ContractAddress, felt252,
        >, // Mapping from token address to oracle address.
        user_points: Map<ContractAddress, PointData>, // Mapping from user address to PointData.
        donations: Map<ContractAddress, u256>, // Mapping from token address to amount donated.
        admin: ContractAddress, // Admin address.
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
        pub const LifeSourceManager_ONLY_ADMIN_CAN_CHANGE: felt252 = 'Only admin can change';
    }

    /// Events
    #[event]
    #[derive(Copy, Drop, Debug, PartialEq, starknet::Event)]
    pub enum Event {
        AddPointFromWeight: AddPointFromWeight,
        RedeemCode: RedeemCode,
        Donated: Donated,
        WithdrawnDonation: WithdrawnDonation,
        ChangedAdmin: ChangedAdmin,
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

    #[derive(Copy, Drop, Debug, PartialEq, starknet::Event)]
    pub struct Donated {
        pub token: ContractAddress,
        pub amount: u256,
    }

    #[derive(Copy, Drop, Debug, PartialEq, starknet::Event)]
    pub struct WithdrawnDonation {
        pub token: ContractAddress,
        pub amount: u256,
    }

    #[derive(Copy, Drop, Debug, PartialEq, starknet::Event)]
    pub struct ChangedAdmin {
        pub new_admin: ContractAddress,
    }

    const POINT_BASIS: u256 = 35;
    const ONE_E18: u256 = 1000000000000000000_u256;
    const ONE_E8: u256 = 100000000_u256;


    #[constructor]
    fn constructor(ref self: ContractState, class_hash: ClassHash) {
        let salt = 0;
        let unique = false;
        let mut calldata = array![];
        let (contract_address, _) = deploy_syscall(class_hash, salt, calldata.span(), unique)
            .unwrap();
        self.token_address.write(contract_address);
        self.price_oracles.entry(self.get_strk_address()).write('STRK/USD');
        self.price_oracles.entry(self.get_eth_address()).write('ETH/USD');
        self.admin.write(get_caller_address());
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
            ref self: ContractState, token: ContractAddress, amount_in_usd: u256,
        ) -> bool {
            let caller = get_caller_address();
            let this_contract = get_contract_address();
            let KEY: felt252 = self.price_oracles.entry(token).read();

            let mut oracle_address: ContractAddress = self.get_oracle_address();

            let (price_of_token_in_usd, price_decimals) = self
                .get_token_price(oracle_address, DataType::SpotEntry(KEY));
            let erc_token = IERC20Dispatcher { contract_address: token };
            let token_decimals = erc_token.decimals();

            let amount_to_send_numerator: u256 = amount_in_usd
                * 10_u256.pow(token_decimals.into())
                * 10_u256.pow(price_decimals.into());

            let amount_to_send_denominator: u256 = price_of_token_in_usd.into();

            let amount_to_send: u256 = amount_to_send_numerator / amount_to_send_denominator;

            erc_token.transfer_from(caller, this_contract, amount_to_send);
            let donation = self.donations.entry(token).read();
            self.donations.entry(token).write(donation + amount_to_send);
            self.emit(Event::Donated(Donated { token, amount: amount_to_send }));

            true
        }

        fn get_usd_to_token_price(
            ref self: ContractState, token: ContractAddress, amount_in_usd: u256,
        ) -> u256 {
            let this_contract = get_contract_address();
            let KEY: felt252 = self.price_oracles.entry(token).read();
            let mut oracle_address: ContractAddress = self.get_oracle_address();
            let (price_of_token_in_usd, price_decimals) = self
                .get_token_price(oracle_address, DataType::SpotEntry(KEY));
            let erc_token = IERC20Dispatcher { contract_address: token };
            let token_decimals = erc_token.decimals();

            let amount_to_send_numerator: u256 = amount_in_usd
                * 10_u256.pow(token_decimals.into())
                * 10_u256.pow(price_decimals.into());

            let amount_to_send_denominator: u256 = price_of_token_in_usd.into();

            let amount_to_send: u256 = amount_to_send_numerator / amount_to_send_denominator;

            amount_to_send
        }

        fn get_donation(self: @ContractState, token: ContractAddress) -> u256 {
            self.donations.entry(token).read()
        }

        fn withdraw_donation(
            ref self: ContractState, token: ContractAddress, amount: u256,
        ) -> bool {
            let caller = get_caller_address();
            assert(caller == self.admin.read(), 'Only admin can withdraw');
            let mut donation = self.donations.entry(token).read();
            assert(donation >= amount, 'Insufficient donation');
            donation = donation - amount;
            self.donations.entry(token).write(donation);
            let erc_token = IERC20Dispatcher { contract_address: token };
            let success = erc_token.transfer(caller, amount);
            assert(success == true, 'Transfer failed');
            self.emit(Event::WithdrawnDonation(WithdrawnDonation { token, amount }));
            true
        }


        fn change_admin(ref self: ContractState, new_admin: ContractAddress) {
            let caller = get_caller_address();
            assert(caller == self.admin.read(), Errors::LifeSourceManager_ONLY_ADMIN_CAN_CHANGE);
            self.admin.write(new_admin);
            self.emit(Event::ChangedAdmin(ChangedAdmin { new_admin }));
        }

        fn get_token_price(
            self: @ContractState, oracle_address: ContractAddress, asset: DataType,
        ) -> (u128, u32) {
            let oracle_dispatcher = IPragmaABIDispatcher { contract_address: oracle_address };
            let output: PragmaPricesResponse = oracle_dispatcher
                .get_data(asset, AggregationMode::Median(()));
            return (output.price, output.decimals);
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
                0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d,
            >()
        }
        fn get_eth_address(self: @ContractState) -> ContractAddress {
            contract_address_const::<
                0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7,
            >()
        }
        fn get_oracle_address(self: @ContractState) -> ContractAddress {
            contract_address_const::<
                0x036031daa264c24520b11d93af622c848b2499b66b41d611bac95e13cfca131a,
            >()
        }
    }
}
