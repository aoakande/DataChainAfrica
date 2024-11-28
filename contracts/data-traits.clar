(define-trait data-tracking-trait
    (
        ;; Get plan details
        (get-plan-details (uint) (response {
            data-amount: uint,
            duration-blocks: uint,
            price: uint,
            is-active: bool
        } uint))

        ;; Subscribe to plan
        (subscribe-to-plan (uint bool) (response bool uint))

        ;; Get usage details
        (get-usage (principal) (response {
            total-data-used: uint,
            last-updated: uint,
            data-balance: uint,
            plan-expiry: uint,
            plan-type: uint,
            auto-renew: bool,
            rollover-data: uint
        } uint))
    )
)
