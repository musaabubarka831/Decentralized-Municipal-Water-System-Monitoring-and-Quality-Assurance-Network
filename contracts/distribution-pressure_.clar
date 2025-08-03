;; Distribution System Pressure Monitoring Contract
;; Maintains adequate water pressure throughout municipal systems

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-INVALID-INPUT (err u201))
(define-constant ERR-ZONE-NOT-FOUND (err u202))
(define-constant ERR-READING-NOT-FOUND (err u203))
(define-constant MIN-PRESSURE u20)
(define-constant MAX-PRESSURE u80)
(define-constant CRITICAL-LOW-PRESSURE u15)
(define-constant CRITICAL-HIGH-PRESSURE u100)

;; Data Variables
(define-data-var next-zone-id uint u1)
(define-data-var next-reading-id uint u1)
(define-data-var system-status (string-ascii 20) "normal")

;; Data Maps
(define-map pressure-zones
  { zone-id: uint }
  {
    name: (string-ascii 50),
    location: (string-ascii 100),
    target-pressure: uint,
    min-pressure: uint,
    max-pressure: uint,
    operator: principal,
    status: (string-ascii 20),
    created-at: uint
  }
)

(define-map pressure-readings
  { reading-id: uint }
  {
    zone-id: uint,
    pressure-value: uint,
    flow-rate: uint,
    temperature: uint,
    timestamp: uint,
    operator: principal,
    alert-level: (string-ascii 20)
  }
)

(define-map zone-alerts
  { zone-id: uint }
  {
    active-alerts: uint,
    last-alert: uint,
    alert-type: (string-ascii 30),
    resolution-status: (string-ascii 20)
  }
)

(define-map system-metrics
  { metric-type: (string-ascii 30) }
  {
    current-value: uint,
    average-value: uint,
    last-updated: uint
  }
)

;; Read-only functions
(define-read-only (get-zone-info (zone-id uint))
  (map-get? pressure-zones { zone-id: zone-id })
)

(define-read-only (get-pressure-reading (reading-id uint))
  (map-get? pressure-readings { reading-id: reading-id })
)

(define-read-only (get-zone-alerts (zone-id uint))
  (map-get? zone-alerts { zone-id: zone-id })
)

(define-read-only (get-system-status)
  (var-get system-status)
)

(define-read-only (get-system-metric (metric-type (string-ascii 30)))
  (map-get? system-metrics { metric-type: metric-type })
)

(define-read-only (check-pressure-status (pressure uint))
  (if (< pressure CRITICAL-LOW-PRESSURE)
    "critical-low"
    (if (> pressure CRITICAL-HIGH-PRESSURE)
      "critical-high"
      (if (< pressure MIN-PRESSURE)
        "low"
        (if (> pressure MAX-PRESSURE)
          "high"
          "normal"
        )
      )
    )
  )
)

;; Public functions
(define-public (register-pressure-zone
  (name (string-ascii 50))
  (location (string-ascii 100))
  (target-pressure uint)
  (min-pressure uint)
  (max-pressure uint)
  (operator principal))
  (let (
    (zone-id (var-get next-zone-id))
  )
    (asserts! (> (len name) u0) ERR-INVALID-INPUT)
    (asserts! (> target-pressure u0) ERR-INVALID-INPUT)
    (asserts! (< min-pressure max-pressure) ERR-INVALID-INPUT)
    (asserts! (and (>= target-pressure min-pressure) (<= target-pressure max-pressure)) ERR-INVALID-INPUT)

    (map-set pressure-zones
      { zone-id: zone-id }
      {
        name: name,
        location: location,
        target-pressure: target-pressure,
        min-pressure: min-pressure,
        max-pressure: max-pressure,
        operator: operator,
        status: "active",
        created-at: block-height
      }
    )

    (map-set zone-alerts
      { zone-id: zone-id }
      {
        active-alerts: u0,
        last-alert: u0,
        alert-type: "none",
        resolution-status: "resolved"
      }
    )

    (var-set next-zone-id (+ zone-id u1))
    (ok zone-id)
  )
)

(define-public (record-pressure-reading
  (zone-id uint)
  (pressure-value uint)
  (flow-rate uint)
  (temperature uint))
  (let (
    (reading-id (var-get next-reading-id))
    (zone-data (unwrap! (get-zone-info zone-id) ERR-ZONE-NOT-FOUND))
    (alert-level (check-pressure-status pressure-value))
  )
    (asserts! (> pressure-value u0) ERR-INVALID-INPUT)
    (asserts! (> flow-rate u0) ERR-INVALID-INPUT)
    (asserts! (and (>= temperature u32) (<= temperature u100)) ERR-INVALID-INPUT)

    (map-set pressure-readings
      { reading-id: reading-id }
      {
        zone-id: zone-id,
        pressure-value: pressure-value,
        flow-rate: flow-rate,
        temperature: temperature,
        timestamp: block-height,
        operator: tx-sender,
        alert-level: alert-level
      }
    )

    ;; Update zone alerts if necessary
    (if (not (is-eq alert-level "normal"))
      (map-set zone-alerts
        { zone-id: zone-id }
        {
          active-alerts: u1,
          last-alert: block-height,
          alert-type: alert-level,
          resolution-status: "pending"
        }
      )
      true
    )

    (var-set next-reading-id (+ reading-id u1))
    (ok reading-id)
  )
)

(define-public (resolve-zone-alert (zone-id uint))
  (let (
    (zone-data (unwrap! (get-zone-info zone-id) ERR-ZONE-NOT-FOUND))
    (alert-data (unwrap! (get-zone-alerts zone-id) ERR-ZONE-NOT-FOUND))
  )
    (asserts! (or (is-eq tx-sender CONTRACT-OWNER)
                  (is-eq tx-sender (get operator zone-data))) ERR-NOT-AUTHORIZED)

    (map-set zone-alerts
      { zone-id: zone-id }
      (merge alert-data {
        active-alerts: u0,
        resolution-status: "resolved"
      })
    )
    (ok true)
  )
)

(define-public (update-system-status (new-status (string-ascii 20)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set system-status new-status)
    (ok true)
  )
)

(define-public (update-zone-target-pressure
  (zone-id uint)
  (new-target-pressure uint))
  (let (
    (zone-data (unwrap! (get-zone-info zone-id) ERR-ZONE-NOT-FOUND))
  )
    (asserts! (or (is-eq tx-sender CONTRACT-OWNER)
                  (is-eq tx-sender (get operator zone-data))) ERR-NOT-AUTHORIZED)
    (asserts! (and (>= new-target-pressure (get min-pressure zone-data))
                   (<= new-target-pressure (get max-pressure zone-data))) ERR-INVALID-INPUT)

    (map-set pressure-zones
      { zone-id: zone-id }
      (merge zone-data { target-pressure: new-target-pressure })
    )
    (ok true)
  )
)

(define-public (emergency-pressure-adjustment
  (zone-id uint)
  (emergency-action (string-ascii 30)))
  (let (
    (zone-data (unwrap! (get-zone-info zone-id) ERR-ZONE-NOT-FOUND))
  )
    (asserts! (or (is-eq tx-sender CONTRACT-OWNER)
                  (is-eq tx-sender (get operator zone-data))) ERR-NOT-AUTHORIZED)

    (map-set zone-alerts
      { zone-id: zone-id }
      {
        active-alerts: u1,
        last-alert: block-height,
        alert-type: emergency-action,
        resolution-status: "emergency-response"
      }
    )
    (ok true)
  )
)
