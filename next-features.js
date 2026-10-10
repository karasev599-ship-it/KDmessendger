(()=>{
const sb=window.supabase.createClient('https://qqofizfqkctycyeafgsa.supabase.co','sb_publishable_MTZuMyuzb0XdtBy3GZIQZw_pHbXc9xK');
const $=q=>document.querySelector(q);
const toast=t=>{const x=$('#toast');if(x){x.textContent=t;x.classList.add('show');setTimeout(()=>x.classList.remove('show'),1800)}};
async function uid(){return (await sb.auth.getSession()).data.session?.user?.id}
async function removeForEveryone(id){const u=await uid();if(!u)return toast('Войди в аккаунт');const r=await sb.from('kd_messages').update({deleted_at:new Date().toISOString(),body:'Сообщение удалено'}).eq('id',id).eq('sender_id',u).select('id').maybeSingle();if(r.error||!r.data)return toast('Не удалось удалить сообщение');document.querySelector(`[data-message-id="${id}"]`)?.remove();toast('Удалено у всех')}
async function deleteLocal(id){const u=await uid();if(!u)return;const r=await sb.from('kd_message_deletions').upsert({user_id:u,message_id:id},{onConflict:'user_id,message_id'});if(r.error)return toast('Не удалось удалить сообщение');document.querySelector(`[data-message-id="${id}"]`)?.remove();toast('Удалено у меня')}
function menu(){document.addEventListener('contextmenu',e=>{const m=e.target.closest('.msg');if(!m)return;e.preventDefault();const id=m.dataset.messageId;if(!id)return;const own=m.classList.contains('out');if(own&&confirm('Удалить сообщение у всех?'))removeForEveryone(id);else if(confirm('Удалить сообщение только у меня?'))deleteLocal(id)})}
function cacheButton(){if(document.querySelector('.kd-cache-btn'))return;const b=document.createElement('button');b.className='bottom-btn kd-cache-btn';b.textContent='🧹 Очистить кэш';b.onclick=async()=>{for(const k of Object.keys(sessionStorage))sessionStorage.removeItem(k);for(const k of Object.keys(localStorage))if(!k.includes('auth-token'))localStorage.removeItem(k);if(window.caches)for(const k of await caches.keys())await caches.delete(k);toast('Кэш очищен');setTimeout(()=>location.reload(),350)};document.querySelector('.sidebar-bottom')?.appendChild(b)}
function boot(){menu();cacheButton()}
setTimeout(boot,1400);
})();