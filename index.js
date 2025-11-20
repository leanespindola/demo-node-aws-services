import express from 'express';
import { v4 as uuidv4 } from 'uuid';
import AWS from 'aws-sdk';

AWS.config.update({ region: 'us-east-1' });

const dynamodb = new AWS.DynamoDB.DocumentClient();

const app = express();
app.use(express.json());

app.get('/health', (req, res) => res.sendStatus(200)); //el target group del load balancer por defecto marca como healthy /item/health, no se por que 

// =============================
//      POST /item  (crear)
// =============================
app.post('/item', async (req, res) => {
  const { name } = req.body;

  if (!name) return res.status(400).send("Falta el campo 'name'");

  const item = {
    id: uuidv4(),
    name
  };

  const params = {
    TableName: "Items",
    Item: item
  };

  try {
    await dynamodb.put(params).promise();
    res.status(201).json(item);
  } catch (err) {
    console.log(err);
    res.status(500).send("Error guardando en DynamoDB");
  }
});

// =============================
//      GET /item/:id  (leer)
// =============================
app.get('/item/:id', async (req, res) => {
  const id = req.params.id;

  const params = {
    TableName: "Items",
    Key: { id }
  };

  try {
    const result = await dynamodb.get(params).promise();

    if (!result.Item) {
      return res.status(404).send("Item no encontrado");
    }

    res.json(result.Item);
  } catch (err) {
    console.log(err);
    res.status(500).send("Error leyendo desde DynamoDB");
  }
});

// =============================
//      SERVIDOR
// =============================
const port = process.env.PORT || 3000;
app.listen(port, () => console.log(`Server corriendo en puerto ${port}`));
