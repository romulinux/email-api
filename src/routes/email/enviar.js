import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { SESClient, SendEmailCommand } from "@aws-sdk/client-ses";
import sanitizeHtml from 'sanitize-html';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const sesClient = new SESClient({ region: "us-east-1" });

const sanitize = function (field) {
  return sanitizeHtml(field, {
    allowedTags: [],
    allowedAttributes: {}
  });
}

export const handler = async (event) => {
  for (const record of event.Records) {
    const MAX_PAYLOAD_SIZE = 10 * 1024; // 10 KB em bytes
    if (record.body.length > MAX_PAYLOAD_SIZE) {
      console.error("❌ Rejeitado: Payload excede o tamanho máximo permitido.");
      continue; // Pula esta mensagem da fila para evitar processamento abusivo
    }

    const body = JSON.parse(record.body);
    let { remetente, destinatario, assunto, mensagem } = body;

    if (!remetente || !destinatario || !assunto || !mensagem) {
      console.error("Dados inválidos:", body);
      continue;
    }

    if (remetente.email.length > 100 || remetente.nome.length > 100 || destinatario.email.length > 100 || destinatario.nome.length > 100 || assunto.length > 128 || mensagem.length > 2048) {
      console.error("Dados inválidos:", body);
      continue;
    }

    remetente.nome = sanitize(remetente.nome);
    remetente.email = sanitize(remetente.email);
    destinatario.nome = sanitize(destinatario.nome);
    destinatario.email = sanitize(destinatario.email);
    assunto = sanitize(assunto);
    mensagem = sanitize(mensagem);

    const regexEmail = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!regexEmail.test(remetente.email)) {
      console.error("E-mail inválido rejeitado:", remetente.email);
      continue; // Pula esta mensagem da fila se o e-mail for malformado
    }
    if (!regexEmail.test(destinatario.email)) {
      console.error("E-mail inválido rejeitado:", destinatario.email);
      continue; // Pula esta mensagem da fila se o e-mail for malformado
    }

    console.log("Remetente:", remetente);
    console.log("Destinatario:", destinatario);
    console.log("Assunto:", assunto);
    console.log("Mensagem:", mensagem);

    let html = mensagem;
    try {
      const template = fs.readFileSync(path.join(__dirname, '..', '..', 'templates', 'email', 'contato.html'), 'utf-8');
      html = template
               .replaceAll('{{remetente.nome}}', remetente.nome)
               .replaceAll('{{remetente.email}}', remetente.email)
               .replaceAll('{{mensagem}}', mensagem);

    } catch (error) {
      console.error("Erro ao ler o template HTML:", error);
    }

    const params = {
      Source: `${remetente.nome} <${remetente.email}>`,
      Destination: { ToAddresses: [destinatario.email] },
      Message: {
        Subject: { Data: assunto },
        Body: {
          Html: { Data: html },
          Text: { Data: mensagem }
        }
      }
    };

    try {
      await sesClient.send(new SendEmailCommand(params));
      console.log(`Email enviado para ${destinatario.email}`);
    } catch (error) {
      console.error("Erro ao enviar email:", error);
      throw error; // Lança o erro para que a mensagem volte para a fila/DLQ
    }
  }
  return { statusCode: 200, body: "Processado com sucesso" };
};