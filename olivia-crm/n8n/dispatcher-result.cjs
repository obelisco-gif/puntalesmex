function prepareResult(response,pending){
 const data=response.body??response;
 const external_id=data.messages?.[0]?.id??null;
 const err=data.error??response.error;
 const code=Number(err?.code);
 const status=Number(response.statusCode??err?.statusCode??err?.httpCode);
 // Only an explicit provider rejection for throttling is retried. Network timeouts are ambiguous.
 const retry_safe=!external_id&&!!data.error&&(status===429||[4,17,32,613,80007,130429].includes(code));
 const error=external_id?null:String(pending.validation_error??err?.message??err?.description??err??'Sin identificador confirmado del proveedor; revisar antes de reintentar').slice(0,1500);
 return {dispatch_id:pending.dispatch_id,processed_count:pending.processed_count,external_id,error,retry_safe};
}
module.exports={prepareResult};
