const express = require('express');
const multer = require('multer');

const router = express.Router();
const store = multer({ dest: 'uploads/' });

router.post('/', store.single('file'), (req, res) => {
  res.status(201).json({ name: req.file.originalname, size: req.file.size });
});

module.exports = router;
