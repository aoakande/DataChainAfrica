;; data-tracking.clar
;; Enhanced contract for tracking mobile data usage with plan management and events

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-invalid-caller (err u101))
(define-constant err-invalid-data (err u102))
(define-constant err-expired-plan (err u103))
(define-constant err-plan-exists (err u104))
(define-constant err-invalid-plan (err u105))

;; Data Plan Types
(define-constant plan-daily u1)
(define-constant plan-weekly u2)
(define-constant plan-monthly u3)

;; Data Structures
(define-map user-data-usage
    { user: principal }
    {
        total-data-used: uint,      ;; in megabytes
        last-updated: uint,         ;; blockchain height
        data-balance: uint,         ;; remaining data in megabytes
        plan-expiry: uint,          ;; expiry block height
        plan-type: uint,            ;; type of plan (daily/weekly/monthly)
        auto-renew: bool,           ;; auto renewal setting
        rollover-data: uint         ;; unused data from previous period
    }
)

(define-map data-plans
    { plan-id: uint }
    {
        data-amount: uint,          ;; in megabytes
        duration-blocks: uint,      ;; plan duration in blocks
        price: uint,                ;; plan price in microSTX
        is-active: bool             ;; whether plan is currently offered
    }
)

(define-map authorized-carriers
    { carrier: principal }
    { is-authorized: bool }
)

;; Events
(define-data-var event-counter uint u0)

(define-map usage-events
    { event-id: uint }
    {
        user: principal,
        usage-amount: uint,
        timestamp: uint,
        carrier: principal,
        remaining-balance: uint
    }
)

;; Public Functions

;; Initialize or update a data plan type
(define-public (set-data-plan (plan-id uint) (data-amount uint) (duration-blocks uint) (price uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) (err err-owner-only))
        (ok (map-set data-plans
            { plan-id: plan-id }
            {
                data-amount: data-amount,
                duration-blocks: duration-blocks,
                price: price,
                is-active: true
            }
        ))
    )
)

;; Subscribe to a data plan
(define-public (subscribe-to-plan (plan-id uint) (auto-renew bool))
    (let
        (
            (user tx-sender)
            (plan (unwrap! (map-get? data-plans { plan-id: plan-id }) (err err-invalid-plan)))
            (current-usage (map-get? user-data-usage { user: user }))
            (rollover-amount (if (is-some current-usage)
                (get rollover-data (unwrap-panic current-usage))
                u0))
        )
        (asserts! (get is-active plan) (err err-invalid-plan))
        
        (ok (map-set user-data-usage
            { user: user }
            {
                total-data-used: u0,
                last-updated: block-height,
                data-balance: (+ (get data-amount plan) rollover-amount),
                plan-expiry: (+ block-height (get duration-blocks plan)),
                plan-type: plan-id,
                auto-renew: auto-renew,
                rollover-data: u0
            }
        ))
    )
)

;; Record data usage with event logging
(define-public (record-usage (user principal) (usage uint))
    (let
        (
            (carrier tx-sender)
            (is-authorized (default-to { is-authorized: false } (map-get? authorized-carriers { carrier: carrier })))
            (current-data (unwrap! (map-get? user-data-usage { user: user }) (err err-invalid-data)))
            (event-id (+ (var-get event-counter) u1))
        )
        (asserts! (get is-authorized is-authorized) (err err-invalid-caller))
        (asserts! (<= usage (get data-balance current-data)) (err err-invalid-data))
        (asserts! (< block-height (get plan-expiry current-data)) (err err-expired-plan))
        
        ;; Update usage data
        (map-set user-data-usage
            { user: user }
            {
                total-data-used: (+ (get total-data-used current-data) usage),
                last-updated: block-height,
                data-balance: (- (get data-balance current-data) usage),
                plan-expiry: (get plan-expiry current-data),
                plan-type: (get plan-type current-data),
                auto-renew: (get auto-renew current-data),
                rollover-data: (get rollover-data current-data)
            }
        )
        
        ;; Log usage event
        (var-set event-counter event-id)
        (ok (map-set usage-events
            { event-id: event-id }
            {
                user: user,
                usage-amount: usage,
                timestamp: block-height,
                carrier: carrier,
                remaining-balance: (- (get data-balance current-data) usage)
            }
        ))
    )
)

;; Handle plan expiry and auto-renewal
(define-public (process-plan-expiry (user principal))
    (let
        (
            (current-data (unwrap! (map-get? user-data-usage { user: user }) (err err-invalid-data)))
            (current-plan (unwrap! (map-get? data-plans { plan-id: (get plan-type current-data) }) (err err-invalid-plan)))
        )
        (asserts! (>= block-height (get plan-expiry current-data)) (err err-invalid-data))
        
        (if (get auto-renew current-data)
            (ok (map-set user-data-usage
                { user: user }
                {
                    total-data-used: u0,
                    last-updated: block-height,
                    data-balance: (+ (get data-amount current-plan) (get data-balance current-data)),
                    plan-expiry: (+ block-height (get duration-blocks current-plan)),
                    plan-type: (get plan-type current-data),
                    auto-renew: true,
                    rollover-data: (get data-balance current-data)
                }
            ))
            (ok (map-set user-data-usage
                { user: user }
                {
                    total-data-used: (get total-data-used current-data),
                    last-updated: block-height,
                    data-balance: u0,
                    plan-expiry: block-height,
                    plan-type: (get plan-type current-data),
                    auto-renew: false,
                    rollover-data: u0
                }
            ))
        )
    )
)

;; Read-only functions

;; Get user's current data usage and plan details
(define-read-only (get-user-data (user principal))
    (map-get? user-data-usage { user: user })
)

;; Get plan details
(define-read-only (get-plan-details (plan-id uint))
    (map-get? data-plans { plan-id: plan-id })
)

;; Get usage event details
(define-read-only (get-usage-event (event-id uint))
    (map-get? usage-events { event-id: event-id })
)

;; Get latest event ID
(define-read-only (get-latest-event-id)
    (var-get event-counter)
)
