;; VoteStake Staking Contract
;; Manages token staking, voting power calculation, and rewards distribution

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u1001))
(define-constant ERR-INSUFFICIENT-BALANCE (err u1002))
(define-constant ERR-INVALID-AMOUNT (err u1003))
(define-constant ERR-STAKE-NOT-FOUND (err u1004))
(define-constant ERR-STAKE-LOCKED (err u1005))
(define-constant ERR-INVALID-PERIOD (err u1006))
(define-constant ERR-CONTRACT-PAUSED (err u1007))
(define-constant ERR-EARLY-UNSTAKE (err u1008))

;; Staking parameters
(define-constant MIN-STAKE-AMOUNT u100)
(define-constant MAX-STAKE-PERIOD u365) ;; 365 days max
(define-constant MIN-STAKE-PERIOD u7)   ;; 7 days min
(define-constant BASE-REWARD-RATE u5)   ;; 5% base rate
(define-constant PENALTY-RATE u10)      ;; 10% early unstake penalty
(define-constant BLOCKS-PER-DAY u144)   ;; Approximate blocks per day

;; Data Variables
(define-data-var contract-paused bool false)
(define-data-var total-staked uint u0)
(define-data-var next-stake-id uint u1)
(define-data-var reward-pool uint u1000000) ;; Initial reward pool

;; Data Maps
(define-map stakes
  { stake-id: uint }
  {
    staker: principal,
    amount: uint,
    start-block: uint,
    period-days: uint,
    reward-rate: uint,
    is-active: bool,
    voting-power: uint
  }
)

(define-map user-stakes
  { user: principal }
  { stake-ids: (list 50 uint), total-staked: uint, total-voting-power: uint }
)

(define-map voting-locks
  { stake-id: uint }
  { locked-until-block: uint, locked-for-proposal: uint }
)

;; Read-only functions

(define-read-only (get-stake-info (stake-id uint))
  (map-get? stakes { stake-id: stake-id })
)

(define-read-only (get-user-stakes (user principal))
  (map-get? user-stakes { user: user })
)

(define-read-only (get-contract-info)
  {
    total-staked: (var-get total-staked),
    reward-pool: (var-get reward-pool),
    is-paused: (var-get contract-paused),
    next-stake-id: (var-get next-stake-id)
  }
)

(define-read-only (calculate-voting-power (amount uint) (period-days uint))
  (let
    (
      (base-power amount)
      (time-multiplier (/ period-days u30)) ;; Bonus for longer periods
      (bonus-power (/ (* base-power time-multiplier) u10))
    )
    (+ base-power bonus-power)
  )
)

(define-read-only (calculate-rewards (stake-id uint))
  (match (get-stake-info stake-id)
    stake-data
    (let
      (
        (amount (get amount stake-data))
        (rate (get reward-rate stake-data))
        (start-block (get start-block stake-data))
        (period-blocks (* (get period-days stake-data) BLOCKS-PER-DAY))
        (elapsed-blocks (- stacks-block-height start-block))
        (effective-blocks (min-uint elapsed-blocks period-blocks))
      )
      (/ (* (* amount rate) effective-blocks) (* u100 period-blocks))
    )
    u0
  )
)

(define-read-only (is-stake-locked (stake-id uint))
  (match (map-get? voting-locks { stake-id: stake-id })
    lock-info (>= (get locked-until-block lock-info) stacks-block-height)
    false
  )
)

(define-read-only (get-user-total-voting-power (user principal))
  (match (get-user-stakes user)
    user-data (get total-voting-power user-data)
    u0
  )
)

;; Private functions

(define-private (min-uint (a uint) (b uint))
  (if (<= a b) a b)
)

(define-private (calculate-reward-rate (period-days uint))
  (let
    (
      (base-rate BASE-REWARD-RATE)
      (time-bonus (/ period-days u30)) ;; 1% bonus per 30 days
    )
    (min-uint (+ base-rate time-bonus) u20) ;; Cap at 20%
  )
)

(define-private (update-user-stakes (user principal) (stake-id uint) (amount uint) (voting-power uint) (is-adding bool))
  (let
    (
      (current-data (default-to 
        { stake-ids: (list), total-staked: u0, total-voting-power: u0 }
        (get-user-stakes user)
      ))
    )
    (if is-adding
      (map-set user-stakes 
        { user: user }
        {
          stake-ids: (unwrap-panic (as-max-len? (append (get stake-ids current-data) stake-id) u50)),
          total-staked: (+ (get total-staked current-data) amount),
          total-voting-power: (+ (get total-voting-power current-data) voting-power)
        }
      )
      (map-set user-stakes
        { user: user }
        {
          stake-ids: (get stake-ids current-data), ;; Keep stake IDs for history
          total-staked: (- (get total-staked current-data) amount),
          total-voting-power: (- (get total-voting-power current-data) voting-power)
        }
      )
    )
  )
)

;; Public functions

(define-public (stake-tokens (amount uint) (period-days uint))
  (let
    (
      (stake-id (var-get next-stake-id))
      (reward-rate (calculate-reward-rate period-days))
      (voting-power (calculate-voting-power amount period-days))
    )
    (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED)
    (asserts! (>= amount MIN-STAKE-AMOUNT) ERR-INVALID-AMOUNT)
    (asserts! (and (>= period-days MIN-STAKE-PERIOD) (<= period-days MAX-STAKE-PERIOD)) ERR-INVALID-PERIOD)
    
    ;; Create stake record
    (map-set stakes
      { stake-id: stake-id }
      {
        staker: tx-sender,
        amount: amount,
        start-block: stacks-block-height,
        period-days: period-days,
        reward-rate: reward-rate,
        is-active: true,
        voting-power: voting-power
      }
    )
    
    ;; Update user stakes
    (update-user-stakes tx-sender stake-id amount voting-power true)
    
    ;; Update contract state
    (var-set total-staked (+ (var-get total-staked) amount))
    (var-set next-stake-id (+ stake-id u1))
    
    (print { event: "stake-created", stake-id: stake-id, staker: tx-sender, amount: amount, voting-power: voting-power })
    (ok stake-id)
  )
)

(define-public (unstake-tokens (stake-id uint))
  (let
    (
      (stake-data (unwrap! (get-stake-info stake-id) ERR-STAKE-NOT-FOUND))
      (staker (get staker stake-data))
      (amount (get amount stake-data))
      (start-block (get start-block stake-data))
      (period-days (get period-days stake-data))
      (voting-power (get voting-power stake-data))
      (period-blocks (* period-days BLOCKS-PER-DAY))
      (is-early (< (- stacks-block-height start-block) period-blocks))
      (penalty (if is-early (/ (* amount PENALTY-RATE) u100) u0))
      (final-amount (- amount penalty))
      (rewards (calculate-rewards stake-id))
    )
    (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED)
    (asserts! (is-eq staker tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (get is-active stake-data) ERR-STAKE-NOT-FOUND)
    (asserts! (not (is-stake-locked stake-id)) ERR-STAKE-LOCKED)
    
    ;; Deactivate stake
    (map-set stakes
      { stake-id: stake-id }
      (merge stake-data { is-active: false })
    )
    
    ;; Update user stakes
    (update-user-stakes tx-sender stake-id amount voting-power false)
    
    ;; Update contract state
    (var-set total-staked (- (var-get total-staked) amount))
    
    ;; Update reward pool (penalties go to pool)
    (if (> penalty u0)
      (var-set reward-pool (+ (var-get reward-pool) penalty))
      true
    )
    
    (print { 
      event: "stake-unstaked", 
      stake-id: stake-id, 
      staker: tx-sender, 
      amount: final-amount, 
      rewards: rewards, 
      penalty: penalty 
    })
    (ok { amount: final-amount, rewards: rewards, penalty: penalty })
  )
)

(define-public (lock-stake-for-vote (stake-id uint) (proposal-id uint) (lock-blocks uint))
  (let
    (
      (stake-data (unwrap! (get-stake-info stake-id) ERR-STAKE-NOT-FOUND))
    )
    (asserts! (is-eq (get staker stake-data) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (get is-active stake-data) ERR-STAKE-NOT-FOUND)
    
    (map-set voting-locks
      { stake-id: stake-id }
      { locked-until-block: (+ stacks-block-height lock-blocks), locked-for-proposal: proposal-id }
    )
    
    (print { event: "stake-locked", stake-id: stake-id, proposal-id: proposal-id })
    (ok true)
  )
)

;; Admin functions

(define-public (toggle-pause)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set contract-paused (not (var-get contract-paused)))
    (print { event: "contract-pause-toggled", paused: (var-get contract-paused) })
    (ok (var-get contract-paused))
  )
)

(define-public (add-to-reward-pool (amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set reward-pool (+ (var-get reward-pool) amount))
    (print { event: "reward-pool-increased", amount: amount, new-total: (var-get reward-pool) })
    (ok (var-get reward-pool))
  )
)


