module.exports=function buildEmailProfile($json){
const j=$json.job;
if(!j?.job_id)return null;
const attributes={email:j.email};
if(j.first_name)attributes.first_name=j.first_name;
if(j.kind==='klaviyo_early_access') attributes.properties={sadiet_contact_id:j.contact_id,bf2026_early_access:true,bf2026_source:'sadiet_crm'};
return {json:{...j,profile_body:{data:{type:'profile',attributes}}}};
};
