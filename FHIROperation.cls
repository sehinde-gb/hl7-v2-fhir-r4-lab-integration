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
        Set ^LabIntegrationDebug("FHIROperationEntered") = 1
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
        Set httpStatus = httpRequest.Post("/csp/healthshare/hl7clean/fhir/r4/Observation")
        Set ^LabIntegrationDebug("HTTPPostStatus") = httpStatus
        Set ^LabIntegrationDebug("HTTPResponseStatus") = httpRequest.HttpResponse.StatusCode
        Set ^LabIntegrationDebug("WWWAuthenticate") = httpRequest.HttpResponse.GetHeader("WWW-Authenticate")
        Set ^LabIntegrationDebug("HTTPResponseBody") = httpRequest.HttpResponse.Data.Read()
        Quit $$$OK
    }
}
