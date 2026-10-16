# HL7 v2 to FHIR R4 Laboratory Integration

A healthcare integration project built with InterSystems HealthShare / IRIS ObjectScript.

The project receives an HL7 v2 ORU^R01 laboratory result, validates the source message, maps the clinical data to a FHIR R4 Observation, and sends the resulting resource to an InterSystems FHIR R4 server using an authenticated HTTP request.

## Integration Flow

HL7 ORU^R01
→ Business Service
→ Business Process
→ HL7 validation
→ HL7-to-FHIR mapping
→ FHIR R4 Observation
→ Business Operation
→ HTTP POST
→ FHIR R4 Server

## HL7 Source

The integration processes laboratory results containing data such as:

- Patient identifier from PID-3
- Observation code and description from OBX-3
- Observation value from OBX-5
- Units from OBX-6
- Reference range from OBX-7
- Observation status from OBX-11
- Observation date/time from OBX-14

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

## FHIR HTTP Integration

The Business Operation:

1. Receives the serialized FHIR Observation.
2. Creates an HTTP request.
3. Sets the FHIR media type headers.
4. Performs HTTP Basic Authentication.
5. POSTs the resource to the FHIR R4 `Observation` endpoint.

Credentials are supplied through InterSystems Production settings rather than being hard-coded in the ObjectScript source.

## End-to-End Verification

The integration has been tested end to end:

1. A synthetic HL7 ORU^R01 laboratory result was placed in the inbound directory.
2. The message was received and validated.
3. A FHIR R4 Observation was constructed.
4. The resource was serialized to FHIR JSON.
5. The Business Operation sent it to the FHIR server.
6. The Observation was persisted by the server.
7. A FHIR `GET /Observation` search returned HTTP `200 OK`.
8. The persisted Observation was retrieved in a FHIR search Bundle.

Example mapped result:

- Observation: Serum Potassium
- Value: 4.7 mmol/L
- Reference range: 3.5–5.1 mmol/L
- Status: final

## Project Classes

### `LaboratoryProcessV2.cls`

Performs HL7 extraction, source validation, HL7-to-FHIR mapping, FHIR R4 object construction, and JSON serialization.

### `FHIRRequest.cls`

Request message used to transport the serialized FHIR resource from the Business Process to the Business Operation.

### `FHIROperation.cls`

Performs authenticated HTTP communication with the FHIR server.

## Security

Authentication credentials are not stored directly in the source code.

The FHIR username and password are configured as InterSystems Production settings and are excluded from this repository.

## Current Scope

This project currently demonstrates a synthetic laboratory-result integration and is intended as a healthcare interoperability learning and portfolio project.

The current implementation focuses on the FHIR R4 Observation workflow rather than representing a complete production clinical integration solution.