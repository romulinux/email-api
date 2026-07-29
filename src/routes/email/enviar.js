import { SESClient, SendEmailCommand } from "@aws-sdk/client-ses";

const sesClient = new SESClient({ region: "us-east-1" });

export const handler = async (event) => {
  for (const record of event.Records) {
    const body = JSON.parse(record.body);
    const { remetente, destinatario, assunto, mensagem } = body;

    const params = {
      Source: `${remetente.nome} <${remetente.email}>`,
      Destination: { ToAddresses: [destinatario.email] },
      Message: {
        Subject: { Data: assunto },
        Body: { Text: { Data: mensagem } }
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