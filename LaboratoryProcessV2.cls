/// 
Class LabIntegration.LaboratoryProcessV2 Extends Ens.BusinessProcess
{

    Method OnRequest(pRequest As %Library.Persistent, Output pResponse As %Library.Persistent) As %Status
    {
   

    // -----------------------------------------
    // 1. Extract and validate message type
    // -----------------------------------------

    Set messageType = pRequest.GetValueAt("MSH:MessageType.MessageCode")
    Set triggerEvent = pRequest.GetValueAt("MSH:MessageType.TriggerEvent")

    Set ^LabIntegrationDebug("MessageType") = messageType
    Set ^LabIntegrationDebug("TriggerEvent") = triggerEvent

    If messageType '= "ORU" {
        Quit $$$ERROR($$$GeneralError, "Unsupported message type")
    }

    If triggerEvent '= "R01" {
        Quit $$$ERROR($$$GeneralError, "Unsupported trigger event")
    }


    // -----------------------------------------
    // 2. Find the PID segment
    // -----------------------------------------

    Set segmentIndex = ""
    Set segmentStatus = $$$OK

    Set pidSegment = pRequest.FindSegment("PID", .segmentIndex, .segmentStatus)



    If '$$$ISOK(segmentStatus) {
        Quit segmentStatus
    }

    If '$IsObject(pidSegment) {
        Quit $$$ERROR($$$GeneralError, "PID segment is missing")
    }


    // -----------------------------------------
    // 3. Extract patient business identity
    // -----------------------------------------

  
    Set patientIdentifier = pidSegment.GetValueAt("3(1).1")
   

    Set patientAssigningAuthority = pidSegment.GetValueAt("3(1).4.1")

    Set ^LabIntegrationDebug("PatientAssigningAuthority") = patientAssigningAuthority
   
    

    // -----------------------------------------
    // 4. Validate patient business identity
    // -----------------------------------------


    If patientIdentifier = "" {
        Quit $$$ERROR($$$GeneralError, "Patient identifier is missing")
    }

    If patientAssigningAuthority '= "NHS" {
        Quit $SYSTEM.Status.Error($$$GeneralError, "Invalid patient assigning authority")
    }

   

    // -----------------------------------------
    // 5. Find the OBX segment
    // -----------------------------------------

    Set segmentIndex = ""
    Set segmentStatus = $$$OK

    Set obxSegment = pRequest.FindSegment("OBX", .segmentIndex, .segmentStatus)

    If '$$$ISOK(segmentStatus)
    {
        Quit segmentStatus
    }

    If '$ISOBJECT(obxSegment) {
        Quit $$$ERROR($$$GeneralError, "OBX segment is missing")
    }

    Set observationValueType = obxSegment.GetValueAt("2")
    Set ^LabIntegrationDebug("ObservationValueType") = observationValueType

    If observationValueType '= "NM" {
        Quit $$$ERROR($$$GeneralError, "Unsupported OBX value type")
    }

    Set observationCode = obxSegment.GetValueAt("3.1")
    Set ^LabIntegrationDebug("ObservationCode") = observationCode

    If observationCode = "" {
        Quit $$$ERROR($$$GeneralError, "Observation code is missing")
    }

    Set observationDescription = obxSegment.GetValueAt("3.2")
    Set ^LabIntegrationDebug("ObservationDescription") = observationDescription

    If observationDescription = "" {
        Quit $$$ERROR($$$GeneralError, "Observation description is missing")
    }

    Set observationValue = obxSegment.GetValueAt("5")
    Set ^LabIntegrationDebug("ObservationValue") = observationValue
    If observationValue = "" {
        Quit $$$ERROR($$$GeneralError, "Observation value is missing")
    }

    If '$ISVALIDNUM(observationValue) {
        Quit $$$ERROR($$$GeneralError, "Observation value is not numeric")
    }

    Set observationUnits = obxSegment.GetValueAt("6")
    Set ^LabIntegrationDebug("ObservationUnits") = observationUnits


    If observationUnits = "" {
        Quit $$$ERROR($$$GeneralError, "Observation units are missing")
    }

    If observationUnits '= "mmol/L" {
        Quit $$$ERROR($$$GeneralError, "Unexpected potassium units")
    }

    Set referenceRange = obxSegment.GetValueAt("7")
    Set ^LabIntegrationDebug("ReferenceRange") = referenceRange

    Set referenceRangeLow = $PIECE(referenceRange, "-", 1)
    Set ^LabIntegrationDebug("ReferenceRangeLow") = referenceRangeLow
    Set referenceRangeHigh = $PIECE(referenceRange, "-", 2)
    Set ^LabIntegrationDebug("ReferenceRangeHigh") = referenceRangeHigh

    If '$ISVALIDNUM(referenceRangeLow) {
        Quit $$$ERROR($$$GeneralError, "Reference range low is not numeric")
    }

    If '$ISVALIDNUM(referenceRangeHigh) {
        Quit $$$ERROR($$$GeneralError, "Reference range high is not numeric")
    }

    If referenceRangeLow >= referenceRangeHigh {
        Quit $$$ERROR($$$GeneralError, "Invalid reference range")
    }

    Set observationStatus = obxSegment.GetValueAt("11")
    Set ^LabIntegrationDebug("ObservationStatus") = observationStatus

    If observationStatus '= "F" {
        Quit $$$ERROR($$$GeneralError, "Unsupported observation status")
    }

    Set observationDateTime = obxSegment.GetValueAt("14")
    Set ^LabIntegrationDebug("ObservationDateTime") = observationDateTime

    If observationDateTime = "" {
        Quit $$$ERROR($$$GeneralError, "Observation date/time is missing")
    }

    If $LENGTH(observationDateTime) '= 14 {
        Quit $$$ERROR($$$GeneralError, "Invalid observation date/time length")
    }

    If observationDateTime '? 14N {
        Quit $$$ERROR($$$GeneralError, "Invalid observation date/time format")
    }

    Set observationYear = $EXTRACT(observationDateTime, 1, 4)
    Set ^LabIntegrationDebug("ObservationYear") = observationYear
    Set observationMonth = $EXTRACT(observationDateTime, 5, 6)
    Set ^LabIntegrationDebug("ObservationMonth") = observationMonth
    Set observationDay = $EXTRACT(observationDateTime, 7, 8)
    Set ^LabIntegrationDebug("ObservationDay") = observationDay
    Set observationHour = $EXTRACT(observationDateTime, 9, 10)
    Set ^LabIntegrationDebug("ObservationHour") = observationHour
    Set observationMinute = $EXTRACT(observationDateTime, 11, 12)
    Set ^LabIntegrationDebug("ObservationMinute") = observationMinute
    Set observationSecond = $EXTRACT(observationDateTime, 13, 14)
    Set ^LabIntegrationDebug("ObservationSecond") = observationSecond

    Set formattedObservationDateTime = observationYear _ "-" _ observationMonth _ "-" _ observationDay _ " " _ observationHour _ ":" _ observationMinute _ ":" _ observationSecond
    Set ^LabIntegrationDebug("FormattedObservationDateTime") = formattedObservationDateTime
    Set validatedObservationDateTime = $ZDATETIMEH(formattedObservationDateTime,3,1,,,,,,,-1)
    Set ^LabIntegrationDebug("ValidatedObservationDateTime") = validatedObservationDateTime
    If validatedObservationDateTime = -1 {
        Quit $$$ERROR($$$GeneralError, "Invalid observation date/time")
    }

    Set fhirObservation = ##class(HS.FHIR.DTL.vR4.Model.Resource.Observation).%New()
    Set fhirObservation.status = "final"
    Set codeableConcept = ##class(HS.FHIR.DTL.vR4.Model.Datatype.CodeableConcept).%New()
    Set codeableConcept.text = observationDescription
    Set fhirObservation.code = codeableConcept
    Set valueQuantity = ##class(HS.FHIR.DTL.vR4.Model.Datatype.Quantity).%New()
    Set valueQuantity.value = observationValue
    Set valueQuantity.unit = observationUnits
    Set fhirObservation.valueQuantity = valueQuantity
    Set fhirReferenceRange = ##class(HS.FHIR.DTL.vR4.Model.Element.Observation.referenceRange).%New()
    Set lowQuantity = ##class(HS.FHIR.DTL.vR4.Model.Datatype.Quantity).%New()
    Set lowQuantity.value = referenceRangeLow
    Set lowQuantity.unit = observationUnits
    Set fhirReferenceRange.low = lowQuantity
    Set highQuantity = ##class(HS.FHIR.DTL.vR4.Model.Datatype.Quantity).%New()
    Set highQuantity.value = referenceRangeHigh
    Set highQuantity.unit = observationUnits
    Set fhirReferenceRange.high = highQuantity
    Do fhirObservation.referenceRange.Insert(fhirReferenceRange)
    Set subjectReference = ##class(HS.FHIR.DTL.vR4.Model.Base.Reference).%New()
    Set subjectIdentifier = ##class(HS.FHIR.DTL.vR4.Model.Datatype.Identifier).%New()
    Set subjectIdentifier.value = patientIdentifier
    Set subjectReference.identifier = subjectIdentifier
    Set fhirObservation.subject = subjectReference
    Set fhirEffectiveDateTime = observationYear _ "-" _ observationMonth _ "-" _ observationDay _ "T" _ observationHour _ ":" _ observationMinute _ ":" _ observationSecond_ "+01:00"
    Set ^LabIntegrationDebug("FHIRDateTimeLocal") = fhirEffectiveDateTime
    Set fhirObservation.effectiveDateTime = fhirEffectiveDateTime
    Set fhirJSONStream = fhirObservation.ToJSON()
    Set fhirJSON = fhirJSONStream.Read()
    Set ^LabIntegrationDebug("FHIREffectiveDateTime") = fhirObservation.effectiveDateTime
    Set ^LabIntegrationDebug("FHIRJSON") = fhirJSON
    Set fhirRequest = ##class(LabIntegration.FHIRRequest).%New()
    Set fhirRequest.FHIRJSON = fhirJSON
    Set sendStatus = ..SendRequestSync("FHIROperation", fhirRequest, .fhirResponse)
    If $$$ISERR(sendStatus) Quit sendStatus
   

    Quit $$$OK
}


    
Method OnResponse(request As %Library.Persistent, ByRef response As %Library.Persistent, callrequest As %Library.Persistent, callresponse As %Library.Persistent, pCompletionKey As %String) As %Status
{
    Quit $$$OK
}

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}