;; RefugeeSafe - Social Recovery Wallet for Displaced Persons
;; Built on Stacks Blockchain in Clarity
;; Trusted contacts (aid workers / advocates) can co-sign to recover access

;; ============================================================
;; CONSTANTS
;; ============================================================

(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-OWNER (err u100))
(define-constant ERR-NOT-TRUSTED (err u101))
(define-constant ERR-ALREADY-TRUSTED (err u102))
(define-constant ERR-NOT-FOUND (err u103))
(define-constant ERR-ALREADY-VOTED (err u104))
(define-constant ERR-RECOVERY-ACTIVE (err u105))
(define-constant ERR-NO-RECOVERY-ACTIVE (err u106))
(define-constant ERR-THRESHOLD-NOT-MET (err u107))
(define-constant ERR-UNAUTHORIZED (err u108))
(define-constant ERR-INVALID-THRESHOLD (err u109))
(define-constant ERR-MAX-TRUSTED (err u110))
(define-constant ERR-INSUFFICIENT-FUNDS (err u111))
(define-constant ERR-SELF-TRUST (err u112))

(define-constant MAX-TRUSTED-CONTACTS u10)
(define-constant RECOVERY-LOCK-PERIOD u144) ;; ~24 hours in blocks

;; ============================================================
;; DATA MAPS & VARS
;; ============================================================

;; Wallet owner (the displaced person)
(define-data-var wallet-owner principal CONTRACT-OWNER)

;; Recovery threshold: number of trusted contacts required to approve recovery
(define-data-var recovery-threshold uint u2)

;; Total trusted contacts count
(define-data-var trusted-count uint u0)

;; Recovery in progress
(define-data-var recovery-active bool false)

;; Proposed new owner during recovery
(define-data-var recovery-candidate principal CONTRACT-OWNER)

;; Block height when recovery was initiated
(define-data-var recovery-initiated-at uint u0)

;; Number of votes collected for current recovery
(define-data-var recovery-votes uint u0)

;; Trusted contacts map: principal -> bool
(define-map trusted-contacts principal bool)

;; Track who has voted in the current recovery round
(define-map recovery-voted principal bool)

;; Aid metadata: store a label per trusted contact (e.g. "UNHCR aid worker")
(define-map contact-label principal (string-ascii 64))

;; ============================================================
;; READ-ONLY FUNCTIONS
;; ============================================================

(define-read-only (get-owner)
  (var-get wallet-owner))

(define-read-only (get-threshold)
  (var-get recovery-threshold))

(define-read-only (get-trusted-count)
  (var-get trusted-count))

(define-read-only (is-trusted (contact principal))
  (default-to false (map-get? trusted-contacts contact)))

(define-read-only (get-contact-label (contact principal))
  (map-get? contact-label contact))

(define-read-only (is-recovery-active)
  (var-get recovery-active))

(define-read-only (get-recovery-candidate)
  (var-get recovery-candidate))

(define-read-only (get-recovery-votes)
  (var-get recovery-votes))

(define-read-only (has-voted (contact principal))
  (default-to false (map-get? recovery-voted contact)))

(define-read-only (get-balance)
  (stx-get-balance (as-contract tx-sender)))

;; ============================================================
;; OWNER FUNCTIONS
;; ============================================================

;; Add a trusted contact (aid worker / advocate)
(define-public (add-trusted-contact (contact principal) (label (string-ascii 64)))
  (begin
    (asserts! (is-eq tx-sender (var-get wallet-owner)) ERR-NOT-OWNER)
    (asserts! (not (is-eq contact (var-get wallet-owner))) ERR-SELF-TRUST)
    (asserts! (not (is-trusted contact)) ERR-ALREADY-TRUSTED)
    (asserts! (< (var-get trusted-count) MAX-TRUSTED-CONTACTS) ERR-MAX-TRUSTED)
    (map-set trusted-contacts contact true)
    (map-set contact-label contact label)
    (var-set trusted-count (+ (var-get trusted-count) u1))
    (ok true)))

;; Remove a trusted contact
(define-public (remove-trusted-contact (contact principal))
  (begin
    (asserts! (is-eq tx-sender (var-get wallet-owner)) ERR-NOT-OWNER)
    (asserts! (is-trusted contact) ERR-NOT-FOUND)
    (map-delete trusted-contacts contact)
    (map-delete contact-label contact)
    (var-set trusted-count (- (var-get trusted-count) u1))
    (ok true)))

;; Update recovery threshold
(define-public (set-threshold (new-threshold uint))
  (begin
    (asserts! (is-eq tx-sender (var-get wallet-owner)) ERR-NOT-OWNER)
    (asserts! (> new-threshold u0) ERR-INVALID-THRESHOLD)
    (asserts! (<= new-threshold (var-get trusted-count)) ERR-INVALID-THRESHOLD)
    (var-set recovery-threshold new-threshold)
    (ok true)))

;; Owner sends STX from the wallet
(define-public (send-stx (recipient principal) (amount uint))
  (begin
    (asserts! (is-eq tx-sender (var-get wallet-owner)) ERR-NOT-OWNER)
    (asserts! (not (var-get recovery-active)) ERR-RECOVERY-ACTIVE)
    (asserts! (>= (stx-get-balance (as-contract tx-sender)) amount) ERR-INSUFFICIENT-FUNDS)
    (as-contract (stx-transfer? amount tx-sender recipient))))

;; Owner deposits STX into the wallet
(define-public (deposit (amount uint))
  (stx-transfer? amount tx-sender (as-contract tx-sender)))

;; Cancel an active recovery (only current owner can do this)
(define-public (cancel-recovery)
  (begin
    (asserts! (is-eq tx-sender (var-get wallet-owner)) ERR-NOT-OWNER)
    (asserts! (var-get recovery-active) ERR-NO-RECOVERY-ACTIVE)
    (var-set recovery-active false)
    (var-set recovery-votes u0)
    (var-set recovery-candidate CONTRACT-OWNER)
    (ok true)))

;; ============================================================
;; SOCIAL RECOVERY FUNCTIONS
;; ============================================================

;; A trusted contact initiates recovery on behalf of displaced person
;; proposing a new owner address
(define-public (initiate-recovery (new-owner principal))
  (begin
    (asserts! (is-trusted tx-sender) ERR-NOT-TRUSTED)
    (asserts! (not (var-get recovery-active)) ERR-RECOVERY-ACTIVE)
    ;; First vote is cast by the initiator
    (var-set recovery-active true)
    (var-set recovery-candidate new-owner)
    (var-set recovery-initiated-at stacks-block-height)
    (var-set recovery-votes u1)
    (map-set recovery-voted tx-sender true)
    (ok true)))

;; Another trusted contact votes to approve recovery
(define-public (approve-recovery)
  (begin
    (asserts! (is-trusted tx-sender) ERR-NOT-TRUSTED)
    (asserts! (var-get recovery-active) ERR-NO-RECOVERY-ACTIVE)
    (asserts! (not (has-voted tx-sender)) ERR-ALREADY-VOTED)
    (map-set recovery-voted tx-sender true)
    (var-set recovery-votes (+ (var-get recovery-votes) u1))
    (ok true)))

;; Execute recovery once threshold is reached and lock period has passed
;; Anyone can call this once conditions are satisfied
(define-public (execute-recovery)
  (begin
    (asserts! (var-get recovery-active) ERR-NO-RECOVERY-ACTIVE)
    (asserts! (>= (var-get recovery-votes) (var-get recovery-threshold)) ERR-THRESHOLD-NOT-MET)
    (asserts! (>= stacks-block-height (+ (var-get recovery-initiated-at) RECOVERY-LOCK-PERIOD)) ERR-UNAUTHORIZED)
    ;; Transfer ownership
    (var-set wallet-owner (var-get recovery-candidate))
    ;; Reset recovery state
    (var-set recovery-active false)
    (var-set recovery-votes u0)
    (var-set recovery-candidate CONTRACT-OWNER)
    (ok true)))

;; ============================================================
;; EMERGENCY FAST RECOVERY
;; Fast-track if ALL trusted contacts approve (no lock period needed)
;; ============================================================

(define-public (execute-emergency-recovery)
  (begin
    (asserts! (var-get recovery-active) ERR-NO-RECOVERY-ACTIVE)
    ;; Require unanimous vote from all trusted contacts
    (asserts! (>= (var-get recovery-votes) (var-get trusted-count)) ERR-THRESHOLD-NOT-MET)
    (asserts! (> (var-get trusted-count) u0) ERR-NOT-FOUND)
    ;; Transfer ownership immediately
    (var-set wallet-owner (var-get recovery-candidate))
    ;; Reset recovery state
    (var-set recovery-active false)
    (var-set recovery-votes u0)
    (var-set recovery-candidate CONTRACT-OWNER)
    (ok true)))

;; ============================================================
;; CONTRACT INITIALIZATION
;; ============================================================

;; Set initial owner explicitly (can be called once at deploy time)
(define-public (initialize (owner principal) (threshold uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-OWNER)
    (asserts! (> threshold u0) ERR-INVALID-THRESHOLD)
    (var-set wallet-owner owner)
    (var-set recovery-threshold threshold)
    (ok true)))