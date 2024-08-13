// index.js
const express = require('express');
const admin = require('firebase-admin');

// Inicialize o Firebase Admin SDK
admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  databaseURL: "https://seu-projeto.firebaseio.com"
});

const db = admin.firestore();
const app = express();

app.use(express.json());

app.post('/api/notificacao', async (req, res) => {
    const resultado = req.body;
    const paymentId = resultado.id;
    const statusPagamento = resultado.charges[0].status;

    try {
        await db.collection("subscriptions").doc(paymentId).update({
            status_pagamento: statusPagamento
        });
        res.status(200).send('Status do pagamento atualizado com sucesso!');
    } catch (error) {
        res.status(500).send('Erro ao atualizar o status do pagamento: ' + error.message);
    }
});

app.listen(3000, () => {
    console.log('Servidor rodando na porta 3000');
});

module.exports = app;
