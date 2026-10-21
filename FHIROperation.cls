/// 
Class LabIntegration.FHIROperation Extends Ens.BusinessOperation
{
    Property FHIRUsername As %String;
    Property FHIRPassword As %String;
    Parameter SETTINGS = "FHIRUsername,FHIRPassword";
    XData MessageMap
{
<MapItems>
    <MapItem MessageType="LabIntegration.FHIRRequest">
        <Method>OnMessage</Method>
    </MapItem>
</MapItems>
}

    Method OnMessage(pRequest As LabIntegration.FHIRRequest, Output pResponse As %Library.Persistent) As %Status
    {
        
        Set fhirJSON = pRequest.FHIRJSON
        Set httpRequest = ##class(%Net.HttpRequest).%New()
        Set httpRequest.Username = ..FHIRUsername
        Set httpRequest.Password = ..FHIRPassword
        Set httpRequest.InitiateAuthentication = "Basic"
        Set httpRequest.Server = "localhost"
        Set httpRequest.Port = 52773
        Set httpRequest.ContentType = "application/fhir+json"
        Do httpRequest.SetHeader("Accept","application/fhir+json")
        Do httpRequest.EntityBody.Write(fhirJSON)
        Kill ^LabIntegrationDebug("HTTPResponseStatus")
        Kill ^LabIntegrationDebug("FHIRCreateResult")
        Kill ^LabIntegrationDebug("FHIRFailureType")
        Kill ^LabIntegrationDebug("Location")
        Kill ^LabIntegrationDebug("ETag")
        Kill ^LabIntegrationDebug("LastModified")
        Kill ^LabIntegrationDebug("HTTPResponseBody")
        Set httpStatus = httpRequest.Post("/csp/healthshare/hl7clean/fhir/r4/Observation")
        If $$$ISOK(httpStatus) Set ^LabIntegrationDebug("FHIRTransportResult") = "SUCCESS"
        If $$$ISERR(httpStatus) Set ^LabIntegrationDebug("FHIRTransportResult") = "FAILURE"
        If $$$ISERR(httpStatus) Quit httpStatus
        If $$$ISOK(httpStatus) {
            Set responseStatus = httpRequest.HttpResponse.StatusCode      
            If responseStatus = 201 Set ^LabIntegrationDebug("FHIRCreateResult") = "SUCCESS"
            If (responseStatus '= 201) Set ^LabIntegrationDebug("FHIRCreateResult") = "FAILURE"
            If (responseStatus '= 201) Set httpFailureStatus = $SYSTEM.Status.Error($$$GeneralError,"FHIR server returned HTTP status "_responseStatus)
           
            If (responseStatus >= 400) && (responseStatus <= 499) Set ^LabIntegrationDebug("FHIRFailureType") = "CLIENT"
            If (responseStatus >= 500) && (responseStatus <= 599) Set ^LabIntegrationDebug("FHIRFailureType") = "SERVER"
            Set ^LabIntegrationDebug("HTTPResponseStatus") = responseStatus
            Set ^LabIntegrationDebug("Location") = httpRequest.HttpResponse.GetHeader("Location")
            Set ^LabIntegrationDebug("ETag") = httpRequest.HttpResponse.GetHeader("ETag")
            Set ^LabIntegrationDebug("LastModified") = httpRequest.HttpResponse.GetHeader("Last-Modified")
            Set ^LabIntegrationDebug("HTTPResponseBody") = httpRequest.HttpResponse.Data.Read()
            If (responseStatus '= 201) Quit httpFailureStatus    
        }
        Quit $$$OK
    }
}
