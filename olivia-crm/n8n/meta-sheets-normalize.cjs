function normalizeMetaRow(row){
 const text=value=>value===null||value===undefined?'':String(value).trim();
 const identifier=(value,prefix)=>text(value).replace(new RegExp('^'+prefix+':','i'),'');
 const external_lead_id=identifier(row.id??row.external_lead_id,'l');
 if(!external_lead_id)throw new Error('La fila de Meta no incluye id de lead');
 if(typeof row.id==='number'&&!Number.isSafeInteger(row.id))throw new Error('El ID de Meta ha perdido precisión: debe llegar como texto');
 const email=text(row['correo_electrónico']??row.email).toLowerCase()||null;
 let phone=text(row['número_de_whatsapp']??row.phone).replace(/^p:/i,'').replace(/[\s().-]/g,'');
 if(phone.startsWith('00'))phone='+'+phone.slice(2);
 if(phone&&!phone.startsWith('+')&&/^34\d{9}$/.test(phone))phone='+'+phone;
 if(phone&&!/^\+[1-9]\d{6,14}$/.test(phone))throw new Error('El móvil necesita prefijo internacional; no se ha supuesto un país');
 if(email&&!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))throw new Error('Email del formulario no válido');
 if(!email&&!phone)throw new Error('La fila no incluye email ni WhatsApp');
 const date=text(row.created_time??row.submitted_at);
 const normalizedDate=date.replace(/([+-]\d{2})(\d{2})$/,'$1:$2');
 if(date&&!Number.isFinite(Date.parse(normalizedDate)))throw new Error('La fecha de Meta no es válida');
 return {external_lead_id,first_name:text(row['nombre_y_apellidos']??row.first_name)||null,email,phone:phone||null,submitted_at:date?new Date(normalizedDate).toISOString():null,form_id:identifier(row.form_id,'f')||null,form_name:text(row.form_name)||null,ad_id:identifier(row.ad_id,'a')||null,ad_name:text(row.ad_name)||null,adset_id:identifier(row.adset_id,'as')||null,adset_name:text(row.adset_name)||null,campaign_id:identifier(row.campaign_id,'c')||null,utm_campaign:text(row.campaign_name)||'bf2026_early_access',utm_source:'meta',platform:text(row.platform)||null,source_sheet:'EA26',source_sheet_id:'11LxXyAzPdGBv5SOBt0gojUCRSiUQAXq6BCdE1scnkTs',source_tab:'Hoja 1',consent_email:false,consent_whatsapp:false,privacy_accepted:false,consent_text:null};
}
module.exports={normalizeMetaRow};
