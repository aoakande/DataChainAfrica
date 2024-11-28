;; marketplace.clar

;; Import traits
(use-trait data-tracking-trait .data-traits.data-tracking-trait)

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u300))
(define-constant err-invalid-listing (err u301))
(define-constant err-insufficient-data (err u302))
(define-constant err-listing-expired (err u303))
(define-constant err-not-seller (err u304))
(define-constant err-insufficient-funds (err u305))

;; Data Structures
(define-map data-listings
    { listing-id: uint }
    {
        seller: principal,
        data-amount: uint,
        price: uint,
        expiry: uint,
        is-active: bool
    }
)

(define-map user-sales
    { user: principal }
    {
        total-sales: uint,
        total-data-sold: uint,
        active-listings: uint
    }
)

(define-data-var listing-counter uint u0)

;; Private Functions
(define-private (process-payment (amount uint) (sender principal) (recipient principal))
    (if (is-ok (stx-transfer? amount sender recipient))
        (ok true)
        (err err-insufficient-funds)))

;; Public Functions
(define-public (create-listing 
    (data-amount uint) 
    (price uint) 
    (blocks-active uint)
    (tracking-contract <data-tracking-trait>))
    (let
        ((listing-id (+ (var-get listing-counter) u1))
         (user-data (unwrap! (contract-call? tracking-contract get-usage tx-sender)
                            (err err-insufficient-data))))
        (asserts! (>= (get data-balance user-data) data-amount)
                 (err err-insufficient-data))
        (begin
            (var-set listing-counter listing-id)
            (map-set data-listings
                { listing-id: listing-id }
                {
                    seller: tx-sender,
                    data-amount: data-amount,
                    price: price,
                    expiry: (+ block-height blocks-active),
                    is-active: true
                }
            )
            (let ((current-sales (default-to
                    { total-sales: u0, total-data-sold: u0, active-listings: u0 }
                    (map-get? user-sales { user: tx-sender }))))
                (map-set user-sales
                    { user: tx-sender }
                    {
                        total-sales: (get total-sales current-sales),
                        total-data-sold: (get total-data-sold current-sales),
                        active-listings: (+ (get active-listings current-sales) u1)
                    }
                ))
            (ok listing-id))))

(define-public (cancel-listing (listing-id uint))
    (let ((listing (unwrap! (map-get? data-listings { listing-id: listing-id })
                           (err err-invalid-listing))))
        (asserts! (is-eq (get seller listing) tx-sender) (err err-not-seller))
        (asserts! (get is-active listing) (err err-listing-expired))
        (begin
            (map-set data-listings
                { listing-id: listing-id }
                {
                    seller: (get seller listing),
                    data-amount: (get data-amount listing),
                    price: (get price listing),
                    expiry: (get expiry listing),
                    is-active: false
                }
            )
            (let ((current-sales (unwrap! (map-get? user-sales { user: tx-sender })
                                        (err err-not-seller))))
                (map-set user-sales
                    { user: tx-sender }
                    {
                        total-sales: (get total-sales current-sales),
                        total-data-sold: (get total-data-sold current-sales),
                        active-listings: (- (get active-listings current-sales) u1)
                    }
                ))
            (ok true))))

(define-public (purchase-listing 
    (listing-id uint) 
    (tracking-contract <data-tracking-trait>))
    (let
        ((listing (unwrap! (map-get? data-listings { listing-id: listing-id })
                          (err err-invalid-listing))))
        (begin
            (asserts! (get is-active listing) (err err-listing-expired))
            (asserts! (<= block-height (get expiry listing)) (err err-listing-expired))
            
            ;; Process payment with proper error handling
            (unwrap! (process-payment (get price listing) tx-sender (get seller listing))
                    (err err-insufficient-funds))
            
            ;; Update listing status
            (map-set data-listings
                { listing-id: listing-id }
                {
                    seller: (get seller listing),
                    data-amount: (get data-amount listing),
                    price: (get price listing),
                    expiry: (get expiry listing),
                    is-active: false
                }
            )
            
            ;; Update seller stats
            (let ((seller-stats (unwrap! (map-get? user-sales { user: (get seller listing) })
                                       (err err-not-seller))))
                (map-set user-sales
                    { user: (get seller listing) }
                    {
                        total-sales: (+ (get total-sales seller-stats) u1),
                        total-data-sold: (+ (get total-data-sold seller-stats) 
                                          (get data-amount listing)),
                        active-listings: (- (get active-listings seller-stats) u1)
                    }
                ))
            
            (ok true))))

;; Read-only Functions
(define-read-only (get-listing (listing-id uint))
    (map-get? data-listings { listing-id: listing-id }))

(define-read-only (get-user-sales (user principal))
    (map-get? user-sales { user: user }))

(define-read-only (get-listing-count)
    (var-get listing-counter))

(define-read-only (is-listing-active (listing-id uint))
    (match (map-get? data-listings { listing-id: listing-id })
        listing (and (get is-active listing)
                    (<= block-height (get expiry listing)))
        false))

(define-read-only (get-user-active-listings (user principal))
    (let ((sales-data (default-to
            { total-sales: u0, total-data-sold: u0, active-listings: u0 }
            (map-get? user-sales { user: user }))))
        (get active-listings sales-data)))