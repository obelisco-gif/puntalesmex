module.exports=function validateRemoteProfile($,$json){
const j=$('Desempaquetar trabajo').item.json;
const ok=[200,201].includes($json.statusCode);
const profile=$json.body?.data;
const marketing=profile?.attributes?.subscriptions?.email?.marketing??{};
const remoteAt=Date.parse(marketing.consent_timestamp??marketing.last_updated??'');
const localAt=Date.parse(j.consent_at??'');
const revoked=marketing.consent==='UNSUBSCRIBED'&&(!Number.isFinite(remoteAt)||remoteAt>=localAt);
const suppressionReasons=(Array.isArray(marketing.suppression)?marketing.suppression:[]).map(x=>String(x.reason??x.suppression_reason??'').toUpperCase());
const suppressed=(Array.isArray(marketing.suppression)?marketing.suppression:[]).some(x=>['SPAM_REPORT','HARD_BOUNCE','INVALID_EMAIL','USER_SUPPRESSED'].includes(String(x.reason??x.suppression_reason??'').toUpperCase()));
const block_reason=!ok?'profile_api_error':revoked?'remote_unsubscribed':suppressionReasons.includes('HARD_BOUNCE')?'hard_bounce':suppressionReasons.includes('INVALID_EMAIL')?'invalid_email':suppressed?'suppressed':null;
const blocked=!ok||(j.kind==='klaviyo_early_access'&&(revoked||suppressed));
return {json:{...j,profile_id:profile?.id??'',blocked,block_reason,suppression_reasons:suppressionReasons,is_unsubscribe:j.kind==='klaviyo_unsubscribe',already_requested:j.job_payload?.request_accepted===true,error:!ok?'No se pudo actualizar el perfil':revoked?'Baja remota posterior o de fecha desconocida':block_reason==='hard_bounce'?'Klaviyo bloquea este correo por rebote permanente (HARD_BOUNCE)':block_reason==='invalid_email'?'Klaviyo considera inválido este correo':suppressed?'Perfil suprimido: revisión manual':'',subscribe_body:{data:{type:'profile-subscription-bulk-create-job',attributes:{custom_source:'Sadiet BF2026 · formulario/CRM',profiles:{data:[{type:'profile',attributes:{email:j.email,subscriptions:{email:{marketing:{consent:'SUBSCRIBED'}}}}}]}},relationships:{list:{data:{type:'list',id:j.list_id}}}}},unsubscribe_body:{data:{type:'profile-subscription-bulk-delete-job',attributes:{profiles:{data:[{type:'profile',attributes:{email:j.email,subscriptions:{email:{marketing:{consent:'UNSUBSCRIBED'}}}}}]}}}}}};
};
