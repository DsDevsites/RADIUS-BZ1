# RADIUS BZ1

Sistema responsivo para controle dos cones de monitoramento RADIUS BZ1. Frontend React + TypeScript + Vite; autenticação, banco e fotos com Supabase; publicação na Vercel.

## 1. Rodar localmente

Requer Node.js 20.19+ ou 22.12+.

```bash
npm install
npm run dev
```

Sem variáveis Supabase, o dashboard abre em modo de pré-visualização com oito cones demonstrativos. Esse modo não salva dados nem ativa autenticação.

## 2. Configurar Supabase

1. Crie/abra um projeto em https://supabase.com/dashboard.
2. No **SQL Editor**, execute todo o arquivo `supabase/migrations/202610280001_radius_bz1.sql`.
3. Em **Project Settings → API**, copie a Project URL e a publishable key (ou a chave legada anon). Nunca use a `service_role` no navegador.
4. Em Authentication → URL Configuration, configure a URL pública da Vercel como Site URL e adicione-a às Redirect URLs.
5. Em Vercel → Project → Settings → Environment Variables, configure:
   - `VITE_SUPABASE_URL` = Project URL
   - `VITE_SUPABASE_ANON_KEY` = publishable/anon key
   Adicione em Production e Preview e faça redeploy.

## 3. Primeiro administrador

1. Cadastre sua conta pelo formulário de cadastro do site.
2. Confirme o e-mail, se a confirmação estiver habilitada.
3. No Supabase SQL Editor, encontre seu usuário pelo e-mail e execute o comando abaixo substituindo pelo UUID real:
   ```sql
   update public.profiles set role='admin' where id='UUID-DO-USUARIO';
   ```
4. Saia e entre novamente para atualizar o perfil. Nunca deixe uma opção pública de promoção a administrador.

## 4. Deploy Vercel

O repositório é preparado para Vercel e usa `vercel.json` para encaminhar rotas de SPA ao `index.html`. Em Project Settings → Git, confirme `DsDevsites/RADIUS-BZ1` e branch `main`. Framework preset: Vite; Build Command: `npm run build`; Output Directory: `dist`. Configure as variáveis antes do redeploy.

## 5. Dados e fotos

A migration cria oito registros iniciais RBZ1-001 a RBZ1-008 como placeholders. Ajuste TAG, nome e datas reais no painel administrativo. Fotos são armazenadas no bucket `cone-photos`. As fotos são consideradas imagens operacionais não sigilosas; se isso não for adequado, altere o bucket para privado e use URLs assinadas.

## 6. Segurança e movimentações

As tabelas usam RLS. Novos usuários sempre começam com papel `user`; o administrador é promovido manualmente. A função `move_cone` registra retirada/devolução em transação, impede retirada de cone ocupado e exige administrador para enviar para manutenção. O administrador deve consultar periodicamente o histórico no banco; a interface de relatório/histórico avançado e gerenciamento de usuários ainda precisa ser concluída.

## 7. Alertas automáticos

O dashboard identifica vencimentos com data cadastrada, mas o envio proativo de e-mail/push e o processo agendado ainda precisam ser configurados. Para isso, configure uma Supabase Edge Function/cron e um provedor de e-mail ou Web Push, guardando segredos apenas no servidor. Não coloque chaves privadas no frontend.

## 8. PWA

O projeto inclui manifest, ícone SVG e service worker básico. No iPhone, abra o domínio no Safari → Compartilhar → Adicionar à Tela de Início. No Android, use o menu do navegador → Instalar aplicativo. Para ícones PNG específicos de iOS, gere os arquivos de ícone e adicione-os ao diretório `public/icons`.

## Build

```bash
npm run build
```
