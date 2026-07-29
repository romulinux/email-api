async function testarEnvioDeEmail() {
  const apiUrl = "https://0jxe1l2j5j.execute-api.us-east-1.amazonaws.com/prod/api/v1/email/enviar";

  const payload = {
    remetente: {
      email: "romulinux@gmail.com",
      nome: "Romulinux"
    },
    destinatario: {
      email: "romulinux@gmail.com",
      nome: "Rômulo"
    },
    assunto: "Teste da API via Node.js",
    mensagem: "Funcionou! A mensagem passou pelo API Gateway e foi enfileirada no SQS com sucesso."
  };

  try {
    console.log("Enviando requisição para a API...");

    const response = await fetch(apiUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify(payload)
    });

    // Como configuramos o API Gateway para retornar 400 se o JSON for inválido, 
    // ou 200 em caso de sucesso, validamos o status aqui.
    if (response.ok) {
      const data = await response.json();
      console.log("✅ Sucesso (Status 200):");
      console.dir(data, { depth: null, colors: true });
    } else {
      const errorData = await response.text();
      console.error(`❌ Erro (Status ${response.status}):`, errorData);
    }

  } catch (error) {
    console.error("❌ Erro de rede ou na execução do script:", error.message);
  }
}

testarEnvioDeEmail();