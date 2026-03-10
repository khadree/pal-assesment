const request = require("supertest");
const app = require("../src/app");

describe("Health endpoint", () => {

  it("should return healthy", async () => {

    const res = await request(app).get("/health");

    expect(res.statusCode).toEqual(200);
    expect(res.body.status).toBe("healthy");

  });

});