import { useEffect, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import { Bell, BellRing, X } from "lucide-react";

type Props = { supabase: SupabaseClient | null; session: any };
type PushSubscriptionRow = { endpoint: string; keys: { p256dh: string; auth: string } };

function decodeVapidKey(value: string) {
  const padding = "=".repeat((4 - (value.length % 4)) % 4);
  const base64 = (value + padding).replace(/-/g, "+").replace(/_/g, "/");
  const raw = window.atob(base64);
  return Uint8Array.from(raw, (char) => char.charCodeAt(0));
}

export default function PushNotifications({ supabase, session }: Props) {
  const [busy, setBusy] = useState(false);
  const [enabled, setEnabled] = useState(false);
  const [message, setMessage] = useState("");
  const [dismissed, setDismissed] = useState(false);
  const supported = typeof window !== "undefined" && "serviceWorker" in navigator && "PushManager" in window && "Notification" in window;
  const vapidKey = import.meta.env.VITE_VAPID_PUBLIC_KEY as string | undefined;

  useEffect(() => {
    let active = true;
    async function check() {
      if (!supported || !session?.user?.id) return;
      try {
        const registration = await navigator.serviceWorker.getRegistration("/");
        const subscription = await registration?.pushManager.getSubscription();
        if (active) setEnabled(Boolean(subscription));
      } catch { if (active) setEnabled(false); }
    }
    void check();
    return () => { active = false; };
  }, [supported, session?.user?.id]);

  if (!session?.user?.id || dismissed) return null;

  async function enableNotifications() {
    if (!supabase) { setMessage("O banco de dados não está configurado."); return; }
    if (!supported) { setMessage("Este navegador não oferece suporte a notificações push."); return; }
    if (!vapidKey) { setMessage("As notificações ainda precisam ser configuradas pelo administrador do sistema."); return; }
    if (/iPhone|iPad|iPod/.test(navigator.userAgent) && !(window.matchMedia("(display-mode: standalone)").matches || (navigator as Navigator & {standalone?: boolean}).standalone)) {
      setMessage("No iPhone, adicione o RADIUS BZ1 à Tela de Início e abra o ícone instalado para ativar as notificações.");
      return;
    }
    setBusy(true); setMessage("");
    try {
      const permission = Notification.permission === "granted" ? "granted" : await Notification.requestPermission();
      if (permission !== "granted") { setMessage("Permissão não concedida. Ative as notificações nas configurações do navegador."); return; }
      const registration = await navigator.serviceWorker.register("/sw.js", { scope: "/" });
      await navigator.serviceWorker.ready;
      let subscription = await registration.pushManager.getSubscription();
      if (!subscription) subscription = await registration.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: decodeVapidKey(vapidKey) });
      const json = subscription.toJSON();
      const endpoint = json.endpoint;
      const p256dh = json.keys?.p256dh;
      const auth = json.keys?.auth;
      if (!endpoint || !p256dh || !auth) throw new Error("O navegador não retornou as chaves da inscrição.");
      const { error } = await supabase.from("push_subscriptions").upsert({
        user_id: session.user.id, endpoint, p256dh, auth, user_agent: navigator.userAgent, updated_at: new Date().toISOString()
      }, { onConflict: "endpoint" });
      if (error) throw error;
      setEnabled(true);
      setMessage("Notificações ativadas neste celular. Você receberá alertas de vencimento dos cones.");
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Não foi possível ativar as notificações.");
    } finally { setBusy(false); }
  }

  async function disableNotifications() {
    if (!supabase) return;
    setBusy(true); setMessage("");
    try {
      const registration = await navigator.serviceWorker.getRegistration("/");
      const subscription = await registration?.pushManager.getSubscription();
      if (subscription) {
        const endpoint = subscription.endpoint;
        await subscription.unsubscribe();
        const { error } = await supabase.from("push_subscriptions").delete().eq("endpoint", endpoint).eq("user_id", session.user.id);
        if (error) throw error;
      }
      setEnabled(false); setMessage("Notificações desativadas neste celular.");
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Não foi possível desativar as notificações.");
    } finally { setBusy(false); }
  }

  return <aside aria-label="Notificações de vencimento" style={{position:"fixed",right:16,bottom:16,zIndex:45,width:"min(360px,calc(100vw - 32px))",padding:14,border:"1px solid #4b3829",borderRadius:14,background:"#181818",boxShadow:"0 12px 40px #0009",color:"#f4f4f5"}}>
    <div style={{display:"flex",alignItems:"center",justifyContent:"space-between",gap:9,marginBottom:7,color:"#fb923c"}}><div style={{display:"flex",alignItems:"center",gap:9,minWidth:0}}>{enabled ? <BellRing size={19}/> : <Bell size={19}/>}<strong style={{fontSize:13,color:"#f4f4f5"}}>Alertas de vencimento</strong></div><button type="button" onClick={() => setDismissed(true)} aria-label="Fechar painel de notificações" title="Fechar" style={{display:"grid",placeItems:"center",flexShrink:0,width:30,height:30,border:"1px solid #454545",borderRadius:8,background:"transparent",color:"#bdbdbd",cursor:"pointer"}}><X size={17}/></button></div>
    <p style={{fontSize:11,lineHeight:1.5,color:"#bdbdbd",margin:"0 0 11px"}}>Receba avisos dos cones no celular, inclusive quando o site estiver fechado.</p>
    <button type="button" onClick={enabled ? disableNotifications : enableNotifications} disabled={busy} style={{width:"100%",minHeight:42,border:0,borderRadius:9,background:"#f97316",color:"#17100a",fontWeight:700,cursor:busy?"wait":"pointer",opacity:busy?.7:1}}>
      {busy ? "Aguarde..." : enabled ? "Desativar neste celular" : "Ativar notificações"}
    </button>
    {message && <p role="status" style={{fontSize:11,lineHeight:1.5,color:"#f4c79c",margin:"10px 0 0"}}>{message}</p>}
  </aside>;
}
