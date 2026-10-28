/// 
Class LabIntegration.FHIRRequest Extends Ens.Request
{
    Property FHIRJSON As %String(MAXLEN = "");
    Property IdentifierSystem As %String(MAXLEN = "");
    Property IdentifierValue as %String;

Storage Default
{
<Data name="FHIRRequestDefaultData">
<Subscript>"FHIRRequest"</Subscript>
<Value name="1">
<Value>FHIRJSON</Value>
</Value>
<Value name="2">
<Value>IdentifierSystem</Value>
</Value>
<Value name="3">
<Value>IdentifierValue</Value>
</Value>
</Data>
<DefaultData>FHIRRequestDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
