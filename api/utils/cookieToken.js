const cookieToken = (user, res) => {
    const token = user.getJwtToken();

    const secureFlag = process.env.COOKIE_SECURE !== 'false';
    const sameSiteFlag = (process.env.COOKIE_SAMESITE || (secureFlag ? 'none' : 'lax')).toLowerCase();

    const options = {
        expires: new Date(
            Date.now() + Number(process.env.COOKIE_TIME || 7) * 24 * 60 * 60 * 1000
        ),
        httpOnly: true,
        secure: secureFlag,
        sameSite: sameSiteFlag,
    };

    user.password = undefined;
    res.status(200).cookie('token', token, options).json({
        success: true,
        token,
        user,
    });
};

module.exports = cookieToken;