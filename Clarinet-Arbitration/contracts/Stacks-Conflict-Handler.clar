;; Dispute Resolution Smart Contract for Stacks Blockchain

;; Error constants
(define-constant ERR_NOT_AUTHORIZED (err u1001))
(define-constant ERR_INVALID_DISPUTE (err u1002))
(define-constant ERR_DISPUTE_NOT_FOUND (err u1003))
(define-constant ERR_ALREADY_RESOLVED (err u1004))
(define-constant ERR_INSUFFICIENT_FUNDS (err u1005))
(define-constant ERR_INVALID_STATUS (err u1006))
(define-constant ERR_NO_RESOLUTION (err u1007))
(define-constant ERR_TIMEOUT_NOT_REACHED (err u1008))
(define-constant ERR_INVALID_ARBITER (err u1009))
(define-constant ERR_TRANSFER_FAILED (err u1010))
(define-constant ERR_INVALID_PARAMETER (err u1011)) ;; New error for parameter validation
(define-constant ERR_EVIDENCE_LIMIT (err u1012)) ;; New error for evidence limit

;; Data variables
(define-data-var contract-owner principal tx-sender)
(define-data-var dispute-counter uint u0)
(define-data-var arbitration-fee uint u100) ;; In microSTX

;; Status enums
(define-constant STATUS_PENDING u1)
(define-constant STATUS_EVIDENCE_PERIOD u2)
(define-constant STATUS_DELIBERATION u3)
(define-constant STATUS_RESOLVED u4)
(define-constant STATUS_CANCELLED u5)

;; Resolution types
(define-constant RESOLUTION_CLAIMANT_WINS u1)
(define-constant RESOLUTION_RESPONDENT_WINS u2)
(define-constant RESOLUTION_SPLIT u3)

;; Map for storing disputes
(define-map disputes
  uint ;; dispute-id
  {
    claimant: principal,
    respondent: principal,
    arbiter: principal,
    amount: uint,
    status: uint,
    resolution: (optional uint),
    evidence-deadline: uint,
    resolution-deadline: uint,
    description: (string-ascii 256)
  }
)

;; Map for storing evidence hashes
(define-map evidence
  { dispute-id: uint, party: principal }
  (list 10 (string-ascii 64)) ;; List of evidence hashes (IPFS or similar)
)

;; Public functions

;; Initialize contract
(define-public (initialize (new-owner principal) (fee uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_NOT_AUTHORIZED)
    ;; Validate new owner is not null
    (asserts! (not (is-eq new-owner 'SP000000000000000000002Q6VF78)) ERR_INVALID_PARAMETER)
    ;; Validate fee is reasonable
    (asserts! (and (>= fee u10) (<= fee u10000)) ERR_INVALID_PARAMETER)
    (var-set contract-owner new-owner)
    (var-set arbitration-fee fee)
    (ok true)
  )
)

;; Create a new dispute
(define-public (create-dispute 
  (respondent principal) 
  (arbiter principal)
  (amount uint)
  (evidence-period uint)
  (resolution-period uint)
  (description (string-ascii 256))
)
  (let 
    (
      (dispute-id (+ (var-get dispute-counter) u1))
      (required-amount (+ amount (var-get arbitration-fee)))
      (current-block-height block-height)
    )
    
    ;; Validate inputs
    (asserts! (> amount u0) ERR_INSUFFICIENT_FUNDS)
    (asserts! (not (is-eq tx-sender respondent)) ERR_INVALID_DISPUTE)
    (asserts! (not (is-eq tx-sender arbiter)) ERR_INVALID_ARBITER)
    (asserts! (not (is-eq respondent arbiter)) ERR_INVALID_ARBITER)
    
    ;; Validate periods are reasonable
    (asserts! (and (>= evidence-period u10) (<= evidence-period u10000)) ERR_INVALID_PARAMETER)
    (asserts! (and (>= resolution-period u10) (<= resolution-period u10000)) ERR_INVALID_PARAMETER)
    
    ;; Validate description is not empty
    (asserts! (> (len description) u0) ERR_INVALID_PARAMETER)
    
    ;; Calculate deadlines after validation
    (let
      (
        (evidence-deadline (+ current-block-height evidence-period))
        (resolution-deadline (+ evidence-deadline resolution-period))
      )
      
      ;; Transfer funds to contract
      (asserts! (is-ok (stx-transfer? required-amount tx-sender (as-contract tx-sender))) ERR_INSUFFICIENT_FUNDS)
      
      ;; Create dispute
      (map-set disputes dispute-id {
        claimant: tx-sender,
        respondent: respondent,
        arbiter: arbiter,
        amount: amount,
        status: STATUS_PENDING,
        resolution: none,
        evidence-deadline: evidence-deadline,
        resolution-deadline: resolution-deadline,
        description: description
      })
      
      ;; Increment counter
      (var-set dispute-counter dispute-id)
      
      (ok dispute-id)
    )
  )
)

;; Accept a dispute (respondent)
(define-public (accept-dispute (dispute-id uint))
  (let 
    (
      (dispute (unwrap! (map-get? disputes dispute-id) ERR_DISPUTE_NOT_FOUND))
    )
    
    ;; Validate caller is respondent
    (asserts! (is-eq tx-sender (get respondent dispute)) ERR_NOT_AUTHORIZED)
    (asserts! (is-eq (get status dispute) STATUS_PENDING) ERR_INVALID_STATUS)
    
    ;; Transfer arbitration fee
    (asserts! (is-ok (stx-transfer? (var-get arbitration-fee) tx-sender (as-contract tx-sender))) ERR_INSUFFICIENT_FUNDS)
    
    ;; Update status
    (map-set disputes dispute-id (merge dispute { status: STATUS_EVIDENCE_PERIOD }))
    
    (ok true)
  )
)

;; Submit evidence
(define-public (submit-evidence (dispute-id uint) (evidence-hash (string-ascii 64)))
  (let 
    (
      (dispute (unwrap! (map-get? disputes dispute-id) ERR_DISPUTE_NOT_FOUND))
    )
    
    ;; Validate caller is a party in the dispute
    (asserts! (or 
      (is-eq tx-sender (get claimant dispute)) 
      (is-eq tx-sender (get respondent dispute))
    ) ERR_NOT_AUTHORIZED)
    
    ;; Check status
    (asserts! (is-eq (get status dispute) STATUS_EVIDENCE_PERIOD) ERR_INVALID_STATUS)
    
    ;; Check deadline
    (asserts! (<= block-height (get evidence-deadline dispute)) ERR_TIMEOUT_NOT_REACHED)
    
    ;; Validate evidence hash is not empty
    (asserts! (> (len evidence-hash) u0) ERR_INVALID_PARAMETER)
    
    ;; Get current evidence safely
    (let
      (
        (current-evidence (default-to (list) (map-get? evidence { dispute-id: dispute-id, party: tx-sender })))
      )
      
      ;; Check if we can add more evidence
      (asserts! (< (len current-evidence) u10) ERR_EVIDENCE_LIMIT)
      
      ;; Store evidence - using as-max-len? to ensure we don't exceed the list limit
      (map-set evidence 
        { dispute-id: dispute-id, party: tx-sender } 
        (unwrap! (as-max-len? (append current-evidence evidence-hash) u10) ERR_EVIDENCE_LIMIT)
      )
      
      (ok true)
    )
  )
)

;; Close evidence period and move to deliberation
(define-public (close-evidence-period (dispute-id uint))
  (let 
    (
      (dispute (unwrap! (map-get? disputes dispute-id) ERR_DISPUTE_NOT_FOUND))
    )
    
    ;; Check if evidence period has ended or arbiter is closing
    (asserts! (or 
      (> block-height (get evidence-deadline dispute))
      (is-eq tx-sender (get arbiter dispute))
    ) ERR_TIMEOUT_NOT_REACHED)
    
    ;; Check status
    (asserts! (is-eq (get status dispute) STATUS_EVIDENCE_PERIOD) ERR_INVALID_STATUS)
    
    ;; Update status
    (map-set disputes dispute-id (merge dispute { status: STATUS_DELIBERATION }))
    
    (ok true)
  )
)

;; Resolve dispute (arbiter only)
(define-public (resolve-dispute (dispute-id uint) (resolution-type uint))
  (let 
    (
      (dispute (unwrap! (map-get? disputes dispute-id) ERR_DISPUTE_NOT_FOUND))
    )
    
    ;; Validate caller is arbiter
    (asserts! (is-eq tx-sender (get arbiter dispute)) ERR_NOT_AUTHORIZED)
    
    ;; Check status
    (asserts! (is-eq (get status dispute) STATUS_DELIBERATION) ERR_INVALID_STATUS)
    
    ;; Check resolution type
    (asserts! (or 
      (is-eq resolution-type RESOLUTION_CLAIMANT_WINS)
      (is-eq resolution-type RESOLUTION_RESPONDENT_WINS)
      (is-eq resolution-type RESOLUTION_SPLIT)
    ) ERR_INVALID_STATUS)
    
    ;; Update dispute
    (map-set disputes dispute-id (merge dispute { 
      status: STATUS_RESOLVED,
      resolution: (some resolution-type)
    }))
    
    ;; Distribute funds based on resolution
    (let
      (
        (claimant (get claimant dispute))
        (respondent (get respondent dispute))
        (amount (get amount dispute))
        (half-amount (/ amount u2))
      )
      
      (if (is-eq resolution-type RESOLUTION_CLAIMANT_WINS)
        (asserts! (is-ok (as-contract (stx-transfer? amount tx-sender claimant))) ERR_TRANSFER_FAILED)
        (if (is-eq resolution-type RESOLUTION_RESPONDENT_WINS)
          (asserts! (is-ok (as-contract (stx-transfer? amount tx-sender respondent))) ERR_TRANSFER_FAILED)
          ;; Split case
          (begin
            (asserts! (is-ok (as-contract (stx-transfer? half-amount tx-sender claimant))) ERR_TRANSFER_FAILED)
            (asserts! (is-ok (as-contract (stx-transfer? half-amount tx-sender respondent))) ERR_TRANSFER_FAILED)
          )
        )
      )
      
      ;; Return arbitration fees to arbiter
      (asserts! (is-ok (as-contract (stx-transfer? (* (var-get arbitration-fee) u2) tx-sender (get arbiter dispute)))) ERR_TRANSFER_FAILED)
      
      (ok true)
    )
  )
)

;; Cancel dispute and refund (only available if not accepted)
(define-public (cancel-dispute (dispute-id uint))
  (let 
    (
      (dispute (unwrap! (map-get? disputes dispute-id) ERR_DISPUTE_NOT_FOUND))
    )
    
    ;; Validate caller is claimant
    (asserts! (is-eq tx-sender (get claimant dispute)) ERR_NOT_AUTHORIZED)
    
    ;; Check status is pending
    (asserts! (is-eq (get status dispute) STATUS_PENDING) ERR_INVALID_STATUS)
    
    ;; Update dispute
    (map-set disputes dispute-id (merge dispute { status: STATUS_CANCELLED }))
    
    ;; Refund claimant
    (asserts! (is-ok (as-contract (stx-transfer? (+ (get amount dispute) (var-get arbitration-fee)) tx-sender (get claimant dispute)))) ERR_TRANSFER_FAILED)
    
    (ok true)
  )
)

;; Force resolution if arbiter doesn't respond in time
(define-public (force-timeout-resolution (dispute-id uint))
  (let 
    (
      (dispute (unwrap! (map-get? disputes dispute-id) ERR_DISPUTE_NOT_FOUND))
    )
    
    ;; Check if resolution deadline has passed
    (asserts! (> block-height (get resolution-deadline dispute)) ERR_TIMEOUT_NOT_REACHED)
    
    ;; Check status is deliberation
    (asserts! (is-eq (get status dispute) STATUS_DELIBERATION) ERR_INVALID_STATUS)
    
    ;; Update dispute
    (map-set disputes dispute-id (merge dispute { 
      status: STATUS_RESOLVED,
      resolution: (some RESOLUTION_SPLIT)
    }))
    
    ;; Split the amount between parties
    (let 
      (
        (amount (get amount dispute))
        (half-amount (/ amount u2))
        (claimant (get claimant dispute))
        (respondent (get respondent dispute))
      )
      
      ;; Split funds between parties
      (asserts! (is-ok (as-contract (stx-transfer? half-amount tx-sender claimant))) ERR_TRANSFER_FAILED)
      (asserts! (is-ok (as-contract (stx-transfer? half-amount tx-sender respondent))) ERR_TRANSFER_FAILED)
      
      ;; Return arbitration fees to parties instead of arbiter (penalty for not resolving)
      (asserts! (is-ok (as-contract (stx-transfer? (var-get arbitration-fee) tx-sender claimant))) ERR_TRANSFER_FAILED)
      (asserts! (is-ok (as-contract (stx-transfer? (var-get arbitration-fee) tx-sender respondent))) ERR_TRANSFER_FAILED)
      
      (ok true)
    )
  )
)

;; Read-only functions

;; Get dispute details
(define-read-only (get-dispute (dispute-id uint))
  (map-get? disputes dispute-id)
)

;; Get evidence for a dispute
(define-read-only (get-evidence (dispute-id uint) (party principal))
  (map-get? evidence { dispute-id: dispute-id, party: party })
)

;; Get current fee
(define-read-only (get-arbitration-fee)
  (var-get arbitration-fee)
)

;; Get contract owner
(define-read-only (get-owner)
  (var-get contract-owner)
)

;; Get dispute count
(define-read-only (get-dispute-count)
  (var-get dispute-counter)
)