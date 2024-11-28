;; Import trait
(use-trait data-tracking-trait .data-traits.data-tracking-trait)

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u200))
(define-constant err-insufficient-funds (err u201))
(define-constant err-invalid-plan (err u202))
(define-constant err-payment-failed (err u203))
(define-constant err-no-subscription (err u204))

;; Data Structures
(define-map user-subscriptions
    { user: principal }
    {
        current-plan-id: uint,
        last-payment: uint,
        payment-due: uint,
        payment-status: bool,
        subscription-start: uint,
        total-payments: uint
    }
)

(define-map payment-history
    { payment-id: uint }
    {
        user: principal,
        amount: uint,
        timestamp: uint,
        plan-id: uint,
        status: bool
    }
)

(define-data-var payment-counter uint u0)

;; Helper function to process subscription payment
(define-private (process-subscription-payment (price uint) (sender principal))
    (stx-transfer? price sender (as-contract tx-sender)))

;; Helper function to record subscription
(define-private (record-subscription 
    (user principal) 
    (plan-id uint) 
    (price uint)
    (payment-id uint))
    (begin
        (map-set user-subscriptions
            { user: user }
            {
                current-plan-id: plan-id,
                last-payment: block-height,
                payment-due: u0,
                payment-status: true,
                subscription-start: block-height,
                total-payments: price
            }
        )
        
        (map-set payment-history
            { payment-id: payment-id }
            {
                user: user,
                amount: price,
                timestamp: block-height,
                plan-id: plan-id,
                status: true
            }
        )))

;; Read-only functions
(define-read-only (get-subscription (user principal))
    (map-get? user-subscriptions { user: user }))

(define-read-only (get-payment (payment-id uint))
    (map-get? payment-history { payment-id: payment-id }))

(define-read-only (is-payment-due (user principal))
    (let
        ((subscription (default-to 
            {
                current-plan-id: u0,
                last-payment: u0,
                payment-due: u0,
                payment-status: true,
                subscription-start: u0,
                total-payments: u0
            }
            (map-get? user-subscriptions { user: user }))))
        (not (get payment-status subscription))))
