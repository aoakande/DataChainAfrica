;; billing.clar

;; Import traits
(use-trait data-tracking-trait .data-traits.data-tracking-trait)
(use-trait marketplace-trait .data-traits.marketplace-trait)

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u200))
(define-constant err-insufficient-funds (err u201))
(define-constant err-invalid-plan (err u202))
(define-constant err-payment-failed (err u203))
(define-constant err-no-subscription (err u204))
(define-constant err-grace-period-expired (err u205))
(define-constant err-invalid-discount (err u206))

;; Data Structures
(define-map user-subscriptions
    { user: principal }
    {
        current-plan-id: uint,
        last-payment: uint,
        payment-due: uint,
        payment-status: bool,
        subscription-start: uint,
        total-payments: uint,
        grace-period-end: uint,     
        discount-rate: uint         
    }
)

(define-map payment-history
    { payment-id: uint }
    {
        user: principal,
        amount: uint,
        timestamp: uint,
        plan-id: uint,
        status: bool,
        discount-applied: uint      
    }
)

(define-map promotional-rates
    { promo-id: uint }
    {
        discount-percentage: uint,
        valid-until: uint,
        min-subscription-months: uint
    }
)

(define-data-var payment-counter uint u0)
(define-data-var grace-period-blocks uint u144)  ;; Default 24 hours worth of blocks

;; Helper Functions
(define-private (process-subscription-payment (price uint) (sender principal))
    (let
        ((subscription (default-to
            {
                current-plan-id: u0,
                last-payment: u0,
                payment-due: u0,
                payment-status: true,
                subscription-start: u0,
                total-payments: u0,
                grace-period-end: u0,
                discount-rate: u0
            }
            (map-get? user-subscriptions { user: sender }))))
        
        (let
            ((discounted-price (if (> (get discount-rate subscription) u0)
                (* price (- u100 (get discount-rate subscription))) 
                price)))
            (stx-transfer? discounted-price sender (as-contract tx-sender)))))

(define-private (record-subscription 
    (user principal) 
    (plan-id uint) 
    (price uint)
    (payment-id uint)
    (discount-rate uint))
    (begin
        (map-set user-subscriptions
            { user: user }
            {
                current-plan-id: plan-id,
                last-payment: block-height,
                payment-due: u0,
                payment-status: true,
                subscription-start: block-height,
                total-payments: price,
                grace-period-end: (+ block-height (var-get grace-period-blocks)),
                discount-rate: discount-rate
            }
        )
        
        (map-set payment-history
            { payment-id: payment-id }
            {
                user: user,
                amount: price,
                timestamp: block-height,
                plan-id: plan-id,
                status: true,
                discount-applied: discount-rate
            }
        )))

;; Public Functions
(define-public (set-promotional-rate (promo-id uint) (discount uint) (valid-blocks uint) (min-months uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) (err err-owner-only))
        (asserts! (<= discount u100) (err err-invalid-discount))
        (ok (map-set promotional-rates
            { promo-id: promo-id }
            {
                discount-percentage: discount,
                valid-until: (+ block-height valid-blocks),
                min-subscription-months: min-months
            }
        ))))

(define-public (subscribe-and-pay 
    (plan-id uint) 
    (tracking-contract <data-tracking-trait>)
    (promo-id uint))
    (let 
        ((plan-details (unwrap! (contract-call? tracking-contract get-plan-details plan-id) 
                               (err err-invalid-plan)))
         (promo (map-get? promotional-rates { promo-id: promo-id })))
        (let
            ((payment-id (+ (var-get payment-counter) u1))
             (discount-rate (if (and 
                                (is-some promo)
                                (< block-height (get valid-until (unwrap-panic promo))))
                            (get discount-percentage (unwrap-panic promo))
                            u0)))
            (begin
                (unwrap! (process-subscription-payment (get price plan-details) tx-sender)
                        (err err-payment-failed))
                (record-subscription 
                    tx-sender 
                    plan-id 
                    (get price plan-details) 
                    payment-id
                    discount-rate)
                (var-set payment-counter payment-id)
                (unwrap! (contract-call? tracking-contract subscribe-to-plan plan-id true)
                        (err err-invalid-plan))
                (ok true)))))

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
                    (asserts! (not (get payment-status subscription)) 
                             (err err-payment-failed))
                    (asserts! (<= block-height (get grace-period-end subscription))
                             (err err-grace-period-expired))
                    (unwrap! (process-subscription-payment (get price plan-details) user)
                            (err err-payment-failed))
                    (record-subscription 
                        user 
                        (get current-plan-id subscription)
                        (get price plan-details)
                        payment-id
                        (get discount-rate subscription))
                    (var-set payment-counter payment-id)
                    (ok true))))))

;; Read-only Functions
(define-read-only (get-subscription (user principal))
    (map-get? user-subscriptions { user: user }))

(define-read-only (get-payment (payment-id uint))
    (map-get? payment-history { payment-id: payment-id }))

(define-read-only (get-promotional-rate (promo-id uint))
    (map-get? promotional-rates { promo-id: promo-id }))

(define-read-only (get-grace-period)
    (var-get grace-period-blocks))

(define-read-only (is-payment-due (user principal))
    (let
        ((subscription (default-to 
            {
                current-plan-id: u0,
                last-payment: u0,
                payment-due: u0,
                payment-status: true,
                subscription-start: u0,
                total-payments: u0,
                grace-period-end: u0,
                discount-rate: u0
            }
            (map-get? user-subscriptions { user: user }))))
        (not (get payment-status subscription))))

(define-read-only (get-user-payment (payment-id uint) (user principal))
    (let ((payment (map-get? payment-history { payment-id: payment-id })))
        (if (and 
            (is-some payment)
            (is-eq (get user (unwrap-panic payment)) user))
            payment
            none)))

(define-read-only (get-subscription-status (user principal))
    (let ((subscription (default-to
            {
                current-plan-id: u0,
                last-payment: u0,
                payment-due: u0,
                payment-status: false,
                subscription-start: u0,
                total-payments: u0,
                grace-period-end: u0,
                discount-rate: u0
            }
            (map-get? user-subscriptions { user: user }))))
        {
            is-active: (and 
                        (get payment-status subscription)
                        (<= block-height (get grace-period-end subscription))),
            days-remaining: (/ (- (get grace-period-end subscription) block-height) u144),
            current-discount: (get discount-rate subscription)
        }))

(define-read-only (is-promotion-valid (promo-id uint))
    (match (map-get? promotional-rates { promo-id: promo-id })
        promo (> (get valid-until promo) block-height)
        false))

(define-read-only (get-payment-details (payment-id uint))
    (default-to
        {
            user: tx-sender,
            amount: u0,
            timestamp: u0,
            plan-id: u0,
            status: false,
            discount-applied: u0
        }
        (map-get? payment-history { payment-id: payment-id })))
