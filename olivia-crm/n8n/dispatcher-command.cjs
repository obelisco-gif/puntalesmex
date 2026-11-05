function prepareCommand(d,processed_count=0){
 const out={...d,processed_count:Number(processed_count)||0};
 const template=d.delivery_type==='template';
 const image=d.kind==='image';
 const text=['freeform','lead_magnet','checkout_link'].includes(d.delivery_type)&&!image;
 out.route=d.kind==='human_handoff_alert'&&template?1:template?2:image?0:text?3:4;
 let error='';
 if(!d.dispatch_id||!d.phone||!d.phone_number_id)error='Falta identificador o destinatario del envío';
 if(template&&(!d.template_name||!d.template_language||!Array.isArray(d.template_components)))error='Plantilla incompleta';
 if(image&&!/^https:\/\//i.test(d.image_url??''))error='Falta URL HTTPS de imagen';
 if(text&&(!String(d.body??'').trim()||String(d.body).length>4096))error='Texto vacío o demasiado largo';
 if(out.route===4)error='Tipología de salida no compatible';
 out.request={messaging_product:'whatsapp',to:d.phone,type:template?'template':image?'image':'text',...(template?{template:{name:d.template_name,language:{code:d.template_language},components:d.template_components}}:image?{image:{link:d.image_url,...(d.caption?{caption:d.caption}:{})}}:{text:{body:d.body,preview_url:false}})};
 if(error){out.route=4;out.validation_error=error;}
 return out;
}
module.exports={prepareCommand};
