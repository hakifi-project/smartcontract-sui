/// Module: hakifi
module hakifi::HAKIFI {
    use std::string::String;
    use sui::{clock::Clock, event};
    use sui::coin::{Self, Coin};
    use sui::table;
    use sui::vec_set;

    const STATE_PENDING: u8 = 0;
    const STATE_AVAILABLE: u8 = 1;
    const STATE_CLAIMED: u8 = 2;
    const STATE_REFUNDED: u8 = 3;
    const STATE_LIQUIDATED: u8 = 4;
    const STATE_EXPIRED: u8 = 5;
    const STATE_CANCELED: u8 = 6;
    const STATE_INVALID: u8 = 7;

    const TYPE_CREATE: u8= 8;
    const TYPE_UPDATE_AVAILABLE: u8= 9;
    const TYPE_UPDATE_INVALID: u8= 10;
    const TYPE_REFUND: u8= 11;
    const TYPE_CANCEL: u8= 12;
    const TYPE_CLAIM: u8= 13;
    const TYPE_EXPIRED: u8= 14;
    const TYPE_LIQUIDATED: u8= 15;

    const ENotPermission: u64 = 100;

    public struct Insurance<phantom T> has key, store {
        id: UID,
        pool: Coin<T>,
        margin_pool: u64,
        claim_pool: u64,
        hakifi_fund: u64,
        third_party_fund: u64,
        user_insurances: table::Table<String, UserInsurance>,
    }

    public struct UserInsurance has store {
        id_insurance: String,
        buyer: address,
        margin: u64 ,
        claim_amount: u64 ,
        expired_time: u64, 
        open_time: u64 ,
        state: u8 ,
        valid: bool  
    }

    public struct EInsurance has copy, store, drop {
        id_insurance: String,
        buyer: address,
        margin: u64 ,
        claim_amount: u64 ,
        expired_time: u64, 
        open_time: u64 ,
        state: u8 ,
        event_type: u8
    }

    public struct Moderator has key {
        id: UID,
        moderator: vec_set::VecSet<address>
    }

    fun init(ctx: &mut TxContext) {
        let mut moderator = Moderator {
            id: object::new(ctx),
            moderator: vec_set::empty()
        };
        vec_set::insert(&mut moderator.moderator, ctx.sender());
        transfer::share_object(moderator)
    }

    public entry fun create_pool<T>(_: &Moderator, ctx: &mut TxContext){
        let pool = Insurance<T> {
            id: object::new(ctx),
            pool: coin::zero(ctx),
            margin_pool: 0,
            claim_pool: 0,
            hakifi_fund: 0,
            third_party_fund: 0,
            user_insurances: table::new(ctx),

        };
        transfer::share_object(pool);
    }

    public entry fun add_moderator(moderator: &mut Moderator, new_moderator_address: address, ctx: &mut TxContext){
        assert!(vec_set::contains(&moderator.moderator, &ctx.sender()), ENotPermission);
        vec_set::insert(&mut moderator.moderator, new_moderator_address);
    }

    public entry fun delete_moderator(moderator: &mut Moderator, moderator_address: address, ctx: &mut TxContext){
        assert!(vec_set::contains(&moderator.moderator, &ctx.sender()), ENotPermission);
        vec_set::remove(&mut moderator.moderator, &moderator_address);
    }

    public entry fun contains_address(moderator: &Moderator, addr: address): bool {
        vec_set::contains(&moderator.moderator, &addr)
    }

    public entry fun create_insurance<T>(coins: Coin<T>, insurance: &mut Insurance<T>, id_insurance: String, margin: u64, clock: &Clock, ctx: &mut TxContext) {
        let new_isurance = UserInsurance {
            id_insurance: id_insurance,
            buyer: tx_context::sender(ctx),
            margin: margin ,
            claim_amount: 0 ,
            expired_time: 0, 
            open_time: clock.timestamp_ms() ,
            state: STATE_PENDING ,
            valid: true  
        };
        table::add(&mut insurance.user_insurances, id_insurance, new_isurance);
        event::emit(
            EInsurance { 
                id_insurance: id_insurance,
                buyer: tx_context::sender(ctx),
                margin: margin ,
                claim_amount: 0 ,
                expired_time: 0, 
                open_time: clock.timestamp_ms() ,
                state: STATE_PENDING ,
                event_type: TYPE_CREATE  
            }
        );
        insurance.margin_pool = insurance.margin_pool + margin;
        coin::join(&mut insurance.pool, coins);
    }

    public entry fun update_available_insurance<T>(moderator: &Moderator, insurance: &mut Insurance<T>, id_insurance: String, claim_amount: u64, expired_time: u64, ctx: &mut TxContext) {
        assert!(vec_set::contains(&moderator.moderator, &ctx.sender()), ENotPermission);

        let user_insurance = table::borrow_mut(&mut insurance.user_insurances, id_insurance);
        user_insurance.state = STATE_AVAILABLE;
        user_insurance.claim_amount = claim_amount;
        user_insurance.expired_time = expired_time;
        insurance.claim_pool = insurance.claim_pool + claim_amount;
        event::emit( 
            EInsurance { 
                id_insurance: id_insurance,
                buyer: user_insurance.buyer,
                margin: user_insurance.margin ,
                claim_amount: claim_amount ,
                expired_time: expired_time, 
                open_time: user_insurance.open_time,
                state: STATE_AVAILABLE ,
                event_type: TYPE_UPDATE_AVAILABLE  
            }
        );
    }
    
    public entry fun update_invalid_insurance<T>(moderator: &Moderator, insurance: &mut Insurance<T>, id_insurance: String, ctx: &mut TxContext) {
        assert!(vec_set::contains(&moderator.moderator, &ctx.sender()), ENotPermission);

        let user_insurance = table::borrow_mut(&mut insurance.user_insurances, id_insurance);
        user_insurance.state = STATE_INVALID;
        insurance.margin_pool = insurance.margin_pool - user_insurance.margin;
        let margin = user_insurance.margin;
        user_insurance.margin = 0;
        let reward = coin::split(&mut insurance.pool, margin  , ctx);
        transfer::public_transfer(reward, user_insurance.buyer);

        event::emit( 
            EInsurance { 
                id_insurance: id_insurance,
                buyer: user_insurance.buyer,
                margin: 0,
                claim_amount: user_insurance.claim_amount ,
                expired_time: user_insurance.expired_time, 
                open_time: user_insurance.open_time,
                state: STATE_INVALID ,
                event_type: TYPE_UPDATE_INVALID  
            }
        );
    }

    public entry fun refund<T>(moderator: &Moderator, insurance: &mut Insurance<T>, id_insurance: String, ctx: &mut TxContext) {
        assert!(vec_set::contains(&moderator.moderator, &ctx.sender()), ENotPermission);

        let user_insurance = table::borrow_mut(&mut insurance.user_insurances, id_insurance);
        user_insurance.state = STATE_REFUNDED;
        insurance.margin_pool = insurance.margin_pool - user_insurance.margin;
        let margin = user_insurance.margin;
        user_insurance.margin = 0;
        let reward = coin::split(&mut insurance.pool, margin  , ctx);   
        transfer::public_transfer(reward, user_insurance.buyer);

        event::emit( 
            EInsurance { 
                id_insurance: id_insurance,
                buyer: user_insurance.buyer,
                margin: 0,
                claim_amount: user_insurance.claim_amount ,
                expired_time: user_insurance.expired_time, 
                open_time: user_insurance.open_time,
                state: STATE_REFUNDED ,
                event_type: TYPE_REFUND  
            }
        );
    }

    public entry fun cancel<T>(moderator: &Moderator, insurance: &mut Insurance<T>, id_insurance: String, ctx: &mut TxContext) {
        assert!(vec_set::contains(&moderator.moderator, &ctx.sender()), ENotPermission);

        let user_insurance = table::borrow_mut(&mut insurance.user_insurances, id_insurance);
        user_insurance.state = STATE_CANCELED;
        insurance.margin_pool = insurance.margin_pool - user_insurance.margin;
        let margin = user_insurance.margin;
        user_insurance.margin = 0;
        let reward = coin::split(&mut insurance.pool, margin  , ctx);
        transfer::public_transfer(reward, user_insurance.buyer);

        event::emit( 
            EInsurance { 
                id_insurance: id_insurance,
                buyer: user_insurance.buyer,
                margin: 0,
                claim_amount: user_insurance.claim_amount ,
                expired_time: user_insurance.expired_time, 
                open_time: user_insurance.open_time,
                state: STATE_CANCELED ,
                event_type: TYPE_CANCEL  
            }
        );
    }

    public entry fun claim<T>(moderator: &Moderator, insurance: &mut Insurance<T>, id_insurance: String, ctx: &mut TxContext) {
        assert!(vec_set::contains(&moderator.moderator, &ctx.sender()), ENotPermission);

        let user_insurance = table::borrow_mut(&mut insurance.user_insurances, id_insurance);
        user_insurance.state = STATE_CLAIMED;
        insurance.claim_pool = insurance.claim_pool - user_insurance.claim_amount;
        let claim_amount = user_insurance.claim_amount;
        user_insurance.claim_amount = 0;
        let reward = coin::split(&mut insurance.pool, claim_amount , ctx);
        transfer::public_transfer(reward, user_insurance.buyer);

        event::emit( 
            EInsurance { 
                id_insurance: id_insurance,
                buyer: user_insurance.buyer,
                margin: 0,
                claim_amount: 0,
                expired_time: user_insurance.expired_time, 
                open_time: user_insurance.open_time,
                state: STATE_CLAIMED ,
                event_type: TYPE_CLAIM  
            }
        );
    }

    public entry fun expire<T>(moderator: &Moderator, insurance: &mut Insurance<T>, id_insurance: String, ctx: &mut TxContext) {
        assert!(vec_set::contains(&moderator.moderator, &ctx.sender()), ENotPermission);

        let user_insurance = table::borrow_mut(&mut insurance.user_insurances, id_insurance);
        user_insurance.state = STATE_EXPIRED;
        
        event::emit( 
            EInsurance { 
                id_insurance: id_insurance,
                buyer: user_insurance.buyer,
                margin: user_insurance.margin,
                claim_amount:user_insurance.claim_amount,
                expired_time: user_insurance.expired_time, 
                open_time: user_insurance.open_time,
                state: STATE_EXPIRED ,
                event_type: TYPE_EXPIRED  
            }
        );
    }

    public entry fun liquidate<T>(moderator: &Moderator, insurance: &mut Insurance<T>, id_insurance: String, ctx: &mut TxContext) {
        assert!(vec_set::contains(&moderator.moderator, &ctx.sender()), ENotPermission);

        let user_insurance = table::borrow_mut(&mut insurance.user_insurances, id_insurance);
        user_insurance.state = STATE_LIQUIDATED;

        event::emit( 
            EInsurance { 
                id_insurance: id_insurance,
                buyer: user_insurance.buyer,
                margin: user_insurance.margin,
                claim_amount:user_insurance.claim_amount,
                expired_time: user_insurance.expired_time, 
                open_time: user_insurance.open_time,
                state: STATE_LIQUIDATED ,
                event_type: TYPE_LIQUIDATED  
            }
        );
    }

    public entry fun withdrawl_from_pool<T>(moderator: &Moderator, insurance: &mut Insurance<T>, amount: u64, ctx: &mut TxContext) {
        assert!(vec_set::contains(&moderator.moderator, &ctx.sender()), ENotPermission);
        let reward = coin::split(&mut insurance.pool, amount  , ctx);
        transfer::public_transfer(reward, ctx.sender());
    }

}
