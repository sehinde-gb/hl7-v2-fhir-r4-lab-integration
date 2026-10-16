/// 
Class LabIntegration.FHIRRequest Extends Ens.Request
{
    Property FHIRJSON As %String(MAXLEN = "");

Storage Default
{
<Data name="FHIRRequestDefaultData">
<Subscript>"FHIRRequest"</Subscript>
<Value name="1">
<Value>FHIRJSON</Value>
</Value>
</Data>
<DefaultData>FHIRRequestDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
