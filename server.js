const express = require('express');
const bodyParser = require('body-parser');
const app = express();

app.use(bodyParser.urlencoded({ extended: true }));

app.post('/submit', (req, res) => {
    const phone = req.body.phone;
    const code = req.body.code;
    console.log('Número de teléfono:', phone);
    console.log('Código de verificación:', code);
    res.send('Inicio de sesión exitoso');
});

app.listen(3000, () => {
    console.log('Servidor escuchando en el puerto 3000');
});