# HL7 v2 to FHIR R4 Laboratory Integration

A healthcare integration project built with InterSystems HealthShare / IRIS ObjectScript.

The project receives an HL7 v2 ORU^R01 laboratory result, validates the source message, maps the clinical data to a FHIR R4 Observation, and sends the resulting resource to an InterSystems FHIR R4 server using an authenticated HTTP request.

The implementation also provides source-occurrence identification, duplicate suppression, retry-safe failure handling, HTTP/FHIR response diagnostics, and operational traceability.

## Integration Flow

HL7 ORU^R01
-> Business Service
-> LaboratoryProcessV2
-> HL7 source validation
-> HL7-to-FHIR mapping
-> FHIR R4 Observation construction
-> FHIR JSON serialization
-> FHIRRequest
-> FHIROperation
-> Idempotency protection
-> Authenticated HTTP POST
-> FHIR R4 Server
-> Response classification and diagnostics

## HL7 Source

The integration processes laboratory results containing data such as:

- Patient identifier from PID-3
- Observation code and description from OBX-3
- Observation value from OBX-5
- Units from OBX-6
- Reference range from OBX-7
- Observation status from OBX-11
- Observation date/time from OBX-14
- Message control ID from MSH-10
- Observation set ID from OBX-1

## Source Validation

The Business Process validates the incoming HL7 message before constructing a FHIR resource.

Validation includes:

- ORU^R01 message type
- Required PID segment
- Required patient identifier
- Expected patient assigning authority
- Required OBX segment
- Supported OBX value type
- Required observation code and description
- Required numeric observation value
- Required and expected units
- Numeric reference range with low < high
- Supported observation status
- Required HL7 observation timestamp
- Timestamp format and calendar-date validation

Invalid source messages are rejected before FHIR construction.

## HL7 to FHIR Mapping

| HL7 v2 | FHIR R4 Observation |
| --- | --- |
| PID-3.1 | subject.identifier.value |
| OBX-3.2 | code.text |
| OBX-5 | valueQuantity.value |
| OBX-6 | valueQuantity.unit |
| OBX-7 | referenceRange.low / referenceRange.high |
| OBX-11 | status |
| OBX-14 | effectiveDateTime |

The project uses InterSystems FHIR R4 model classes to construct the Observation as an object model before serializing it to JSON.

## Source Occurrence Identity

Each source observation occurrence is assigned an identifier using:

`TRAINING-LAB|<MSH-10>|<OBX-1>`

This combines:

- Source system identity
- HL7 message control ID from MSH-10
- Observation set ID from OBX-1

The identifier is added to the FHIR Observation and is also passed to the Business Operation for idempotency processing.

## Idempotency and Duplicate Suppression

The Business Operation maintains a local processed-occurrence registry keyed by the source occurrence identifier.

Processing follows these rules:

1. Acquire an occurrence-specific lock.
2. Check whether the occurrence has already been successfully processed.
3. If already processed, suppress the duplicate without issuing another FHIR POST.
4. If not processed, continue with the FHIR request.
5. Record the occurrence as processed only after a successful FHIR response.
6. Release the occurrence-specific lock.

This prevents repeated delivery of the same HL7 source occurrence from creating duplicate Observations through the normal integration path.

## Retry and Failure Handling

Failed requests do not mark the source occurrence as successfully processed.

This means the same occurrence can be retried after the underlying problem is corrected.

The implementation distinguishes between:

- Configuration failure
- HTTP transport failure
- FHIR/HTTP response failure
- Successful FHIR creation
- Duplicate suppression

Verified recovery scenarios include:

- Transport failure followed by successful retry of the same occurrence
- HTTP/FHIR failure followed by successful retry of the same occurrence
- Duplicate delivery after successful processing being suppressed

## FHIR HTTP Integration

The Business Operation:

1. Validates that required FHIR authentication settings are configured.
2. Receives the serialized FHIR Observation and source occurrence identity.
3. Applies local idempotency protection.
4. Creates an HTTP request.
5. Sets the FHIR media type headers.
6. Performs HTTP Basic Authentication.
7. Adds an `If-None-Exist` conditional-create header.
8. POSTs the resource to the FHIR R4 `Observation` endpoint.
9. Separately evaluates transport success and the HTTP/FHIR response.
10. Records the occurrence as processed only after successful creation.

Credentials are supplied through InterSystems Production settings rather than being hard-coded in the ObjectScript source.

## Operational Diagnostics

The Business Operation records diagnostic information that allows an operator to identify the source occurrence and determine where a failure occurred.

Diagnostics include information such as:

- Source occurrence identity
- Transport success or failure
- HTTP response status
- FHIR create success or failure
- Client/server failure classification
- HTTP response body
- FHIR OperationOutcome information when returned
- Final idempotency result

OperationOutcome processing captures useful information including severity, issue code, diagnostics, details text, and expression information when available.

This supports boundary-based troubleshooting without requiring already-proven parts of the integration to be repeatedly reopened.

## End-to-End Verification

The integration has been regression-tested across the complete processing path.

Verified behaviour includes:

- Fresh HL7 ORU^R01 processing
- Source validation
- FHIR R4 Observation construction
- FHIR JSON serialization
- Successful HTTP transport
- Successful FHIR creation with HTTP 201
- Successful occurrence registration
- Duplicate suppression
- Transport failure without poisoning the occurrence
- Successful retry after transport recovery
- HTTP/FHIR failure without poisoning the occurrence
- Successful retry after HTTP/FHIR correction
- OperationOutcome capture
- Representative validation rejection before downstream FHIR processing

Example mapped result:

- Observation: Serum Potassium
- Value: 4.7 mmol/L
- Reference range: 3.5-5.1 mmol/L
- Status: final

## Project Classes

### `LaboratoryProcessV2.cls`

Performs HL7 extraction, source validation, HL7-to-FHIR mapping, FHIR R4 object construction, source-occurrence identifier construction, and JSON serialization.

### `FHIRRequest.cls`

Request message used to transport the serialized FHIR resource and source-occurrence identifier information from the Business Process to the Business Operation.

### `FHIROperation.cls`

Performs configuration validation, local idempotency checking, occurrence-specific locking, duplicate suppression, authenticated HTTP communication, FHIR response handling, retry-safe processing, OperationOutcome diagnostics, and successful-occurrence registration.

### `DiagnosticProcess.cls`

A small diagnostic Business Process retained from earlier development and extraction testing.

## Conditional Create and Known Server Limitation

The Business Operation sends an `If-None-Exist` header using the Observation source identifier as an additional FHIR-level idempotency mechanism.

During testing in the current InterSystems FHIR server environment:

- The Observation identifier was persisted successfully.
- Direct resource retrieval worked.
- General FHIR search worked.
- Other search parameters such as status worked.
- Identifier token search did not return the persisted Observation.

Because identifier-based search did not match the persisted identifier in this environment, FHIR Conditional Create could not be relied upon as the primary duplicate-suppression mechanism.

The local processed-occurrence registry therefore provides the verified duplicate protection for this project, while the conditional-create header is retained as a secondary layer.

## Security

Authentication credentials are not stored directly in the source code.

The FHIR username and password are configured as InterSystems Production settings and are excluded from this repository.

## Current Scope

This project demonstrates a synthetic laboratory-result integration and is intended as a healthcare interoperability learning and portfolio project.

The implementation focuses on a FHIR R4 Observation workflow rather than representing a complete production clinical integration solution.

Production deployments would additionally require organisation-specific decisions around areas such as terminology coding, patient and practitioner identity resolution, encounter references, security, deployment configuration, monitoring, and operational governance.