import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { SESClient, SendEmailCommand } from "@aws-sdk/client-ses";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const sesClient = new SESClient({ region: "us-east-1" });

export const handler = async (event) => {
  for (const record of event.Records) {
    const body = JSON.parse(record.body);
    const { remetente, destinatario, assunto, mensagem } = body;

    console.log("Remetente:", remetente);
    console.log("Destinatario:", destinatario);
    console.log("Assunto:", assunto);
    console.log("Mensagem:", mensagem);

    let html = mensagem;
    try {
      const template = fs.readFileSync(path.join(__dirname, '..', '..', 'templates', 'email', 'contato.html'), 'utf-8');
      html = template
               .replace('{remetente.nome}', remetente.nome)
               .replace('{remetente.email}', remetente.email)
               .replace('{mensagem}', mensagem);

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