;; billing.clar

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

;; Public function to subscribe and pay
(define-public (subscribe-and-pay (plan-id uint) (tracking-contract <data-tracking-trait>))
    (let 
        ((plan-details (unwrap! (contract-call? tracking-contract get-plan-details plan-id) 
                               (err err-invalid-plan))))
        (let
            ((payment-id (+ (var-get payment-counter) u1)))
            (begin
                ;; Process payment
                (unwrap! (process-subscription-payment (get price plan-details) tx-sender)
                        (err err-payment-failed))
                ;; Record subscription
                (record-subscription tx-sender plan-id (get price plan-details) payment-id)
                ;; Update counter
                (var-set payment-counter payment-id)
                ;; Subscribe in tracking contract
                (unwrap! (contract-call? tracking-contract subscribe-to-plan plan-id true)
                        (err err-invalid-plan))
                (ok true)))))

;; Process renewal payment
(define-public (process-renewal-payment (user principal) (tracking-contract <data-tracking-trait>))
    (let 
        ((subscription (unwrap! (map-get? user-subscriptions { user: user })
                               (err err-no-subscription))))
        (let 
            ((plan-details (unwrap! (contract-call? tracking-contract get-plan-details 
                                   (get current-plan-id subscription))
                                   (err err-invalid-plan))))
            (let
                ((payment-id (+ (var-get payment-counter) u1)))
                (begin
                    ;; Check payment status
                    (asserts! (not (get payment-status subscription)) 
                             (err err-payment-failed))
                    ;; Process payment
                    (unwrap! (process-subscription-payment (get price plan-details) user)
                            (err err-payment-failed))
                    ;; Record payment
                    (record-subscription user 
                                       (get current-plan-id subscription)
                                       (get price plan-details)
                                       payment-id)
                    ;; Update counter
                    (var-set payment-counter payment-id)
                    (ok true))))))

;; Read-only functions remain unchanged
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
