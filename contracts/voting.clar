;; VoteStake Voting Contract
;; Manages governance proposals and weighted voting based on staked tokens

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u2001))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u2002))
(define-constant ERR-VOTING-CLOSED (err u2003))
(define-constant ERR-ALREADY-VOTED (err u2004))
(define-constant ERR-INSUFFICIENT-STAKE (err u2005))
(define-constant ERR-INVALID-VOTING-PERIOD (err u2006))
(define-constant ERR-PROPOSAL-NOT-PASSED (err u2007))
(define-constant ERR-PROPOSAL-ALREADY-EXECUTED (err u2008))
(define-constant ERR-CONTRACT-PAUSED (err u2009))
(define-constant ERR-VOTING-NOT-ENDED (err u2010))

;; Voting parameters
(define-constant MIN-PROPOSAL-STAKE u1000) ;; Minimum stake to create proposal
(define-constant MIN-VOTING-PERIOD u144)   ;; Minimum 1 day voting period
(define-constant MAX-VOTING-PERIOD u4320)  ;; Maximum 30 days voting period
(define-constant QUORUM-THRESHOLD u10)     ;; 10% of total staked tokens
(define-constant PASS-THRESHOLD u51)       ;; 51% majority to pass
(define-constant EXECUTION-DELAY u144)     ;; 1 day delay before execution

;; Data Variables
(define-data-var contract-paused bool false)
(define-data-var next-proposal-id uint u1)
(define-data-var total-voting-power uint u0)

;; Data Maps
(define-map proposals
  { proposal-id: uint }
  {
    proposer: principal,
    title: (string-ascii 128),
    description: (string-ascii 512),
    start-block: uint,
    end-block: uint,
    yes-votes: uint,
    no-votes: uint,
    total-votes: uint,
    status: (string-ascii 16), ;; "active", "passed", "rejected", "executed"
    execution-block: (optional uint),
    required-stake: uint,
    created-at: uint
  }
)

(define-map votes
  { proposal-id: uint, voter: principal }
  { vote: bool, voting-power: uint, stacks-block-height: uint }
)

(define-map proposal-voters
  { proposal-id: uint }
  { voters: (list 500 principal), voter-count: uint }
)

(define-map user-vote-history
  { user: principal }
  { voted-proposals: (list 100 uint), total-votes-cast: uint }
)

;; Read-only functions

(define-read-only (get-proposal (proposal-id uint))
  (map-get? proposals { proposal-id: proposal-id })
)

(define-read-only (get-vote (proposal-id uint) (voter principal))
  (map-get? votes { proposal-id: proposal-id, voter: voter })
)

(define-read-only (get-proposal-voters (proposal-id uint))
  (map-get? proposal-voters { proposal-id: proposal-id })
)

(define-read-only (get-user-vote-history (user principal))
  (map-get? user-vote-history { user: user })
)

(define-read-only (get-contract-info)
  {
    total-voting-power: (var-get total-voting-power),
    next-proposal-id: (var-get next-proposal-id),
    is-paused: (var-get contract-paused),
    min-proposal-stake: MIN-PROPOSAL-STAKE,
    quorum-threshold: QUORUM-THRESHOLD
  }
)

(define-read-only (get-proposal-results (proposal-id uint))
  (match (get-proposal proposal-id)
    proposal
    (let
      (
        (yes-votes (get yes-votes proposal))
        (no-votes (get no-votes proposal))
        (total-votes (get total-votes proposal))
        (total-staked (var-get total-voting-power))
        (quorum-needed (/ (* total-staked QUORUM-THRESHOLD) u100))
        (has-quorum (>= total-votes quorum-needed))
        (yes-percentage (if (> total-votes u0) (/ (* yes-votes u100) total-votes) u0))
        (passes (and has-quorum (>= yes-percentage PASS-THRESHOLD)))
      )
      (ok {
        yes-votes: yes-votes,
        no-votes: no-votes,
        total-votes: total-votes,
        yes-percentage: yes-percentage,
        quorum-needed: quorum-needed,
        has-quorum: has-quorum,
        passes: passes,
        status: (get status proposal)
      })
    )
    (err ERR-PROPOSAL-NOT-FOUND)
  )
)

(define-read-only (is-voting-active (proposal-id uint))
  (match (get-proposal proposal-id)
    proposal
    (let
      (
        (start-block (get start-block proposal))
        (end-block (get end-block proposal))
        (current-block stacks-block-height)
      )
      (and 
        (>= current-block start-block)
        (<= current-block end-block)
        (is-eq (get status proposal) "active")
      )
    )
    false
  )
)

(define-read-only (can-execute-proposal (proposal-id uint))
  (match (get-proposal proposal-id)
    proposal
    (let
      (
        (status (get status proposal))
        (end-block (get end-block proposal))
        (execution-delay-passed (>= stacks-block-height (+ end-block EXECUTION-DELAY)))
      )
      (and
        (is-eq status "passed")
        execution-delay-passed
      )
    )
    false
  )
)

;; Private functions

(define-private (update-user-vote-history (user principal) (proposal-id uint))
  (let
    (
      (current-history (default-to 
        { voted-proposals: (list), total-votes-cast: u0 }
        (get-user-vote-history user)
      ))
    )
    (map-set user-vote-history
      { user: user }
      {
        voted-proposals: (unwrap-panic (as-max-len? 
          (append (get voted-proposals current-history) proposal-id) u100)),
        total-votes-cast: (+ (get total-votes-cast current-history) u1)
      }
    )
  )
)

(define-private (update-proposal-voters (proposal-id uint) (voter principal))
  (let
    (
      (current-voters (default-to 
        { voters: (list), voter-count: u0 }
        (get-proposal-voters proposal-id)
      ))
    )
    (map-set proposal-voters
      { proposal-id: proposal-id }
      {
        voters: (unwrap-panic (as-max-len? 
          (append (get voters current-voters) voter) u500)),
        voter-count: (+ (get voter-count current-voters) u1)
      }
    )
  )
)

;; Public functions

(define-public (create-proposal (title (string-ascii 128)) (description (string-ascii 512)) (voting-period uint))
  (let
    (
      (proposal-id (var-get next-proposal-id))
      (start-block stacks-block-height)
      (end-block (+ start-block voting-period))
      (user-voting-power u1000) ;; Placeholder - in production would check staking contract
    )
    (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED)
    (asserts! (>= user-voting-power MIN-PROPOSAL-STAKE) ERR-INSUFFICIENT-STAKE)
    (asserts! (and (>= voting-period MIN-VOTING-PERIOD) (<= voting-period MAX-VOTING-PERIOD)) ERR-INVALID-VOTING-PERIOD)
    
    ;; Create proposal
    (map-set proposals
      { proposal-id: proposal-id }
      {
        proposer: tx-sender,
        title: title,
        description: description,
        start-block: start-block,
        end-block: end-block,
        yes-votes: u0,
        no-votes: u0,
        total-votes: u0,
        status: "active",
        execution-block: none,
        required-stake: MIN-PROPOSAL-STAKE,
        created-at: stacks-block-height
      }
    )
    
    ;; Update next proposal ID
    (var-set next-proposal-id (+ proposal-id u1))
    
    ;; Note: In production, would lock proposer's stake in staking contract
    
    (print { 
      event: "proposal-created", 
      proposal-id: proposal-id, 
      proposer: tx-sender, 
      title: title,
      voting-period: voting-period
    })
    (ok proposal-id)
  )
)

(define-public (cast-vote (proposal-id uint) (vote bool))
  (let
    (
      (proposal-data (unwrap! (get-proposal proposal-id) ERR-PROPOSAL-NOT-FOUND))
      (voter-power u1000) ;; Placeholder - in production would check staking contract
      (has-voted (is-some (get-vote proposal-id tx-sender)))
    )
    (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED)
    (asserts! (> voter-power u0) ERR-INSUFFICIENT-STAKE)
    (asserts! (is-voting-active proposal-id) ERR-VOTING-CLOSED)
    (asserts! (not has-voted) ERR-ALREADY-VOTED)
    
    ;; Record the vote
    (map-set votes
      { proposal-id: proposal-id, voter: tx-sender }
      { vote: vote, voting-power: voter-power, stacks-block-height: stacks-block-height }
    )
    
    ;; Update proposal vote counts
    (map-set proposals
      { proposal-id: proposal-id }
      (merge proposal-data {
        yes-votes: (if vote (+ (get yes-votes proposal-data) voter-power) (get yes-votes proposal-data)),
        no-votes: (if vote (get no-votes proposal-data) (+ (get no-votes proposal-data) voter-power)),
        total-votes: (+ (get total-votes proposal-data) voter-power)
      })
    )
    
    ;; Update voter tracking
    (update-proposal-voters proposal-id tx-sender)
    (update-user-vote-history tx-sender proposal-id)
    
    (print { 
      event: "vote-cast", 
      proposal-id: proposal-id, 
      voter: tx-sender, 
      vote: vote, 
      voting-power: voter-power 
    })
    (ok true)
  )
)

(define-public (finalize-proposal (proposal-id uint))
  (let
    (
      (proposal-data (unwrap! (get-proposal proposal-id) ERR-PROPOSAL-NOT-FOUND))
      (end-block (get end-block proposal-data))
      (current-status (get status proposal-data))
      (results (unwrap-panic (get-proposal-results proposal-id)))
      (passes (get passes results))
      (new-status (if passes "passed" "rejected"))
    )
    (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED)
    (asserts! (> stacks-block-height end-block) ERR-VOTING-NOT-ENDED)
    (asserts! (is-eq current-status "active") ERR-VOTING-CLOSED)
    
    ;; Update proposal status
    (map-set proposals
      { proposal-id: proposal-id }
      (merge proposal-data { status: new-status })
    )
    
    (print { 
      event: "proposal-finalized", 
      proposal-id: proposal-id, 
      status: new-status, 
      results: results 
    })
    (ok new-status)
  )
)

(define-public (execute-proposal (proposal-id uint))
  (let
    (
      (proposal-data (unwrap! (get-proposal proposal-id) ERR-PROPOSAL-NOT-FOUND))
    )
    (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED)
    (asserts! (can-execute-proposal proposal-id) ERR-PROPOSAL-NOT-PASSED)
    (asserts! (is-none (get execution-block proposal-data)) ERR-PROPOSAL-ALREADY-EXECUTED)
    
    ;; Mark as executed
    (map-set proposals
      { proposal-id: proposal-id }
      (merge proposal-data { 
        status: "executed", 
        execution-block: (some stacks-block-height) 
      })
    )
    
    (print { 
      event: "proposal-executed", 
      proposal-id: proposal-id, 
      executor: tx-sender,
      execution-block: stacks-block-height
    })
    (ok true)
  )
)

;; Admin functions

(define-public (toggle-pause)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set contract-paused (not (var-get contract-paused)))
    (print { event: "voting-contract-pause-toggled", paused: (var-get contract-paused) })
    (ok (var-get contract-paused))
  )
)

(define-public (update-total-voting-power (new-total uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set total-voting-power new-total)
    (print { event: "total-voting-power-updated", new-total: new-total })
    (ok new-total)
  )
)


