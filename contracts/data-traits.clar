(define-trait data-tracking-trait
    (
        ;; Existing functions
        (get-plan-details (uint) (response {
            data-amount: uint,
            duration-blocks: uint,
            price: uint,
            is-active: bool
        } uint))

        (subscribe-to-plan (uint bool) (response bool uint))

        (get-usage (principal) (response {
            total-data-used: uint,
            last-updated: uint,
            data-balance: uint,
            plan-expiry: uint,
            plan-type: uint,
            auto-renew: bool,
            rollover-data: uint
        } uint))

        ;; New functions for enhanced features
        (update-plan (uint uint uint uint) (response bool uint))

        (get-usage-history (principal uint) (response {
            usage-amount: uint,
            timestamp: uint,
            carrier: principal,
            remaining-balance: uint
        } uint))

        (check-plan-validity (principal) (response bool uint))
    )
)

;; New trait for marketplace functionality
(define-trait marketplace-trait
    (
        (transfer-data (principal principal uint) (response bool uint))
        (list-data-for-sale (principal uint uint) (response bool uint))
        (buy-listed-data (uint) (response bool uint))
    )
)
