;; Customer Water Usage Analytics Contract
;; Detects unusual consumption patterns that may indicate leaks or theft

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u500))
(define-constant ERR-INVALID-INPUT (err u501))
(define-constant ERR-CUSTOMER-NOT-FOUND (err u502))
(define-constant ERR-READING-NOT-FOUND (err u503))
(define-constant NORMAL-USAGE-THRESHOLD u1000)
(define-constant HIGH-USAGE-THRESHOLD u2000)
(define-constant LEAK-DETECTION-THRESHOLD u150)
(define-constant THEFT-DETECTION-THRESHOLD u300)

;; Data Variables
(define-data-var next-customer-id uint u1)
(define-data-var next-reading-id uint u1)
(define-data-var billing-cycle uint u30) ;; days

;; Data Maps
(define-map customers
  { customer-id: uint }
  {
    account-number: (string-ascii 20),
    name: (string-ascii 50),
    address: (string-ascii 100),
    property-type: (string-ascii 30),
    meter-id: (string-ascii 20),
    baseline-usage: uint,
    operator: principal,
    status: (string-ascii 20),
    created-at: uint
  }
)

(define-map usage-readings
  { reading-id: uint }
  {
    customer-id: uint,
    meter-reading: uint,
    usage-volume: uint,
    reading-date: uint,
    reading-type: (string-ascii 20),
    anomaly-detected: bool,
    anomaly-type: (string-ascii 30),
    operator: principal
  }
)

(define-map usage-analytics
  { customer-id: uint }
  {
    average-daily-usage: uint,
    peak-usage: uint,
    low-usage: uint,
    usage-trend: (string-ascii 20),
    last-analysis: uint,
    conservation-score: uint
  }
)

(define-map anomaly-alerts
  { customer-id: uint }
  {
    active-alerts: uint,
    alert-type: (string-ascii 30),
    severity-level: (string-ascii 20),
    detected-at: uint,
    estimated-loss: uint,
    resolution-status: (string-ascii 20)
  }
)

(define-map billing-data
  { customer-id: uint }
  {
    current-bill: uint,
    last-payment: uint,
    payment-status: (string-ascii 20),
    billing-period: uint,
    conservation-credit: uint
  }
)

;; Read-only functions
(define-read-only (get-customer-info (customer-id uint))
  (map-get? customers { customer-id: customer-id })
)

(define-read-only (get-usage-reading (reading-id uint))
  (map-get? usage-readings { reading-id: reading-id })
)

(define-read-only (get-usage-analytics (customer-id uint))
  (map-get? usage-analytics { customer-id: customer-id })
)

(define-read-only (get-anomaly-alert (customer-id uint))
  (map-get? anomaly-alerts { customer-id: customer-id })
)

(define-read-only (get-billing-data (customer-id uint))
  (map-get? billing-data { customer-id: customer-id })
)

(define-read-only (detect-usage-anomaly (current-usage uint) (baseline-usage uint))
  (let (
    (usage-difference (if (> current-usage baseline-usage)
                        (- current-usage baseline-usage)
                        (- baseline-usage current-usage)))
    (percentage-change (/ (* usage-difference u100) baseline-usage))
  )
    (if (> percentage-change THEFT-DETECTION-THRESHOLD)
      "potential-theft"
      (if (> percentage-change LEAK-DETECTION-THRESHOLD)
        "potential-leak"
        (if (> current-usage HIGH-USAGE-THRESHOLD)
          "high-usage"
          "normal"
        )
      )
    )
  )
)

(define-read-only (calculate-conservation-score (usage uint) (baseline uint))
  (if (<= usage baseline)
    (+ u50 (/ (* (- baseline usage) u50) baseline))
    (if (> usage (* baseline u2))
      u0
      (- u50 (/ (* (- usage baseline) u50) baseline))
    )
  )
)

;; Public functions
(define-public (register-customer
  (account-number (string-ascii 20))
  (name (string-ascii 50))
  (address (string-ascii 100))
  (property-type (string-ascii 30))
  (meter-id (string-ascii 20))
  (baseline-usage uint)
  (operator principal))
  (let (
    (customer-id (var-get next-customer-id))
  )
    (asserts! (> (len account-number) u0) ERR-INVALID-INPUT)
    (asserts! (> (len name) u0) ERR-INVALID-INPUT)
    (asserts! (> baseline-usage u0) ERR-INVALID-INPUT)

    (map-set customers
      { customer-id: customer-id }
      {
        account-number: account-number,
        name: name,
        address: address,
        property-type: property-type,
        meter-id: meter-id,
        baseline-usage: baseline-usage,
        operator: operator,
        status: "active",
        created-at: block-height
      }
    )

    (map-set usage-analytics
      { customer-id: customer-id }
      {
        average-daily-usage: baseline-usage,
        peak-usage: baseline-usage,
        low-usage: baseline-usage,
        usage-trend: "stable",
        last-analysis: block-height,
        conservation-score: u50
      }
    )

    (map-set anomaly-alerts
      { customer-id: customer-id }
      {
        active-alerts: u0,
        alert-type: "none",
        severity-level: "none",
        detected-at: u0,
        estimated-loss: u0,
        resolution-status: "resolved"
      }
    )

    (map-set billing-data
      { customer-id: customer-id }
      {
        current-bill: u0,
        last-payment: u0,
        payment-status: "current",
        billing-period: (var-get billing-cycle),
        conservation-credit: u0
      }
    )

    (var-set next-customer-id (+ customer-id u1))
    (ok customer-id)
  )
)

(define-public (record-usage-reading
  (customer-id uint)
  (meter-reading uint)
  (usage-volume uint)
  (reading-type (string-ascii 20)))
  (let (
    (reading-id (var-get next-reading-id))
    (customer-data (unwrap! (get-customer-info customer-id) ERR-CUSTOMER-NOT-FOUND))
    (anomaly-type (detect-usage-anomaly usage-volume (get baseline-usage customer-data)))
    (anomaly-detected (not (is-eq anomaly-type "normal")))
  )
    (asserts! (> meter-reading u0) ERR-INVALID-INPUT)
    (asserts! (> usage-volume u0) ERR-INVALID-INPUT)

    (map-set usage-readings
      { reading-id: reading-id }
      {
        customer-id: customer-id,
        meter-reading: meter-reading,
        usage-volume: usage-volume,
        reading-date: block-height,
        reading-type: reading-type,
        anomaly-detected: anomaly-detected,
        anomaly-type: anomaly-type,
        operator: tx-sender
      }
    )

    ;; Update analytics
    (let (
      (analytics-data (unwrap! (get-usage-analytics customer-id) ERR-CUSTOMER-NOT-FOUND))
      (conservation-score (calculate-conservation-score usage-volume (get baseline-usage customer-data)))
    )
      (map-set usage-analytics
        { customer-id: customer-id }
        (merge analytics-data {
          average-daily-usage: (/ (+ (get average-daily-usage analytics-data) usage-volume) u2),
          peak-usage: (if (> usage-volume (get peak-usage analytics-data)) usage-volume (get peak-usage analytics-data)),
          low-usage: (if (< usage-volume (get low-usage analytics-data)) usage-volume (get low-usage analytics-data)),
          last-analysis: block-height,
          conservation-score: conservation-score
        })
      )
    )

    ;; Create anomaly alert if detected
    (if anomaly-detected
      (let (
        (estimated-loss (if (or (is-eq anomaly-type "potential-leak") (is-eq anomaly-type "potential-theft"))
                          (- usage-volume (get baseline-usage customer-data))
                          u0))
        (severity (if (is-eq anomaly-type "potential-theft") "high"
                    (if (is-eq anomaly-type "potential-leak") "medium" "low")))
      )
        (map-set anomaly-alerts
          { customer-id: customer-id }
          {
            active-alerts: u1,
            alert-type: anomaly-type,
            severity-level: severity,
            detected-at: block-height,
            estimated-loss: estimated-loss,
            resolution-status: "pending"
          }
        )
      )
      true
    )

    (var-set next-reading-id (+ reading-id u1))
    (ok reading-id)
  )
)

(define-public (resolve-anomaly-alert (customer-id uint))
  (let (
    (customer-data (unwrap! (get-customer-info customer-id) ERR-CUSTOMER-NOT-FOUND))
    (alert-data (unwrap! (get-anomaly-alert customer-id) ERR-CUSTOMER-NOT-FOUND))
  )
    (asserts! (or (is-eq tx-sender CONTRACT-OWNER)
                  (is-eq tx-sender (get operator customer-data))) ERR-NOT-AUTHORIZED)

    (map-set anomaly-alerts
      { customer-id: customer-id }
      (merge alert-data {
        active-alerts: u0,
        resolution-status: "resolved"
      })
    )
    (ok true)
  )
)

(define-public (update-baseline-usage
  (customer-id uint)
  (new-baseline uint))
  (let (
    (customer-data (unwrap! (get-customer-info customer-id) ERR-CUSTOMER-NOT-FOUND))
  )
    (asserts! (or (is-eq tx-sender CONTRACT-OWNER)
                  (is-eq tx-sender (get operator customer-data))) ERR-NOT-AUTHORIZED)
    (asserts! (> new-baseline u0) ERR-INVALID-INPUT)

    (map-set customers
      { customer-id: customer-id }
      (merge customer-data { baseline-usage: new-baseline })
    )
    (ok true)
  )
)

(define-public (generate-bill
  (customer-id uint)
  (usage-amount uint)
  (rate-per-unit uint))
  (let (
    (customer-data (unwrap! (get-customer-info customer-id) ERR-CUSTOMER-NOT-FOUND))
    (analytics-data (unwrap! (get-usage-analytics customer-id) ERR-CUSTOMER-NOT-FOUND))
    (bill-amount (* usage-amount rate-per-unit))
    (conservation-credit (if (> (get conservation-score analytics-data) u70) u50 u0))
    (final-bill (if (> bill-amount conservation-credit) (- bill-amount conservation-credit) u0))
  )
    (asserts! (or (is-eq tx-sender CONTRACT-OWNER)
                  (is-eq tx-sender (get operator customer-data))) ERR-NOT-AUTHORIZED)
    (asserts! (> usage-amount u0) ERR-INVALID-INPUT)
    (asserts! (> rate-per-unit u0) ERR-INVALID-INPUT)

    (map-set billing-data
      { customer-id: customer-id }
      {
        current-bill: final-bill,
        last-payment: u0,
        payment-status: "pending",
        billing-period: (var-get billing-cycle),
        conservation-credit: conservation-credit
      }
    )
    (ok final-bill)
  )
)

(define-public (set-billing-cycle (new-cycle uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> new-cycle u0) ERR-INVALID-INPUT)
    (var-set billing-cycle new-cycle)
    (ok true)
  )
)
